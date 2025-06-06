require 'selenium-webdriver'
require 'nokogiri'
require 'json'

class ImprovedSmartStoreCrawler
  def initialize(headless: true)
    @options = Selenium::WebDriver::Chrome::Options.new
    @options.add_argument('--headless') if headless
    @options.add_argument('--no-sandbox')
    @options.add_argument('--disable-dev-shm-usage')
    @options.add_argument('--disable-gpu')
    @options.add_argument('--window-size=1920,1080')
    @options.add_argument('--user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')

    @driver = nil
  end

  def start_driver
    @driver = Selenium::WebDriver.for :chrome, options: @options
    @driver.manage.timeouts.implicit_wait = 5
    @driver
  end

  def stop_driver
    @driver&.quit
  end

  def crawl_smartstore(store_url)
    start_driver

    begin
      puts "스마트스토어 접속: #{store_url}"
      @driver.get(store_url)

      # 페이지 로딩 대기
      sleep(5)

      # 페이지 소스 확인용 (디버깅)
      puts "페이지 타이틀: #{@driver.title}"

      # 실제 페이지 구조 분석
      analyze_page_structure

      # 스토어 정보 추출
      store_info = extract_store_info_v2

      # 상품 목록 추출
      products = extract_products_v2

      {
        store_info: store_info,
        products: products,
        crawled_at: Time.now,
        page_title: @driver.title,
        page_url: @driver.current_url
      }

    rescue => e
      puts "크롤링 에러: #{e.message}"
      puts e.backtrace.first(5)
      nil
    ensure
      stop_driver
    end
  end

  private

  def analyze_page_structure
    puts "\n=== 페이지 구조 분석 ==="

    # 주요 컨테이너들 찾기
    containers = [
      '.content', '.main', '.container', '.wrap',
      '#content', '#main', '#container',
      '[class*="store"]', '[class*="shop"]', '[class*="seller"]'
    ]

    containers.each do |selector|
      elements = @driver.find_elements(css: selector)
      if elements.any?
        puts "#{selector}: #{elements.length}개 발견"
      end
    end

    # 텍스트 내용으로 스토어명 찾기
    begin
      page_text = @driver.find_element(tag_name: 'body').text
      if page_text.include?('스토어') || page_text.include?('상품')
        puts "페이지에서 한국어 콘텐츠 확인됨"
      end
    rescue
      puts "페이지 텍스트 분석 실패"
    end
  end

  def extract_store_info_v2
    store_info = {}

    begin
      # 페이지 타이틀에서 스토어명 추출
      title = @driver.title
      if title && title.length > 0
        store_info[:name] = title.split('|').first&.strip || title.strip
      end

      # 메타 정보에서 설명 추출
      meta_desc = @driver.find_element(xpath: "//meta[@name='description']")&.attribute('content')
      if meta_desc && meta_desc.length > 0
        store_info[:description] = meta_desc
      end

      # 현재 URL 저장
      store_info[:url] = @driver.current_url

      # 다양한 선택자로 스토어명 시도
      store_name_selectors = [
        'h1', 'h2', '.store-name', '.shop-name', '.seller-name',
        '[class*="store"][class*="name"]', '[class*="shop"][class*="name"]',
        '.title', '.name', '.brand'
      ]

      store_name_selectors.each do |selector|
        begin
          element = @driver.find_element(css: selector)
          if element && element.text.length > 0 && element.text.length < 100
            store_info[:extracted_name] = element.text.strip
            break
          end
        rescue Selenium::WebDriver::Error::NoSuchElementException
          next
        end
      end

    rescue => e
      puts "스토어 정보 추출 에러: #{e.message}"
    end

    store_info
  end

  def extract_products_v2
    products = []

    begin
      # 페이지 스크롤하여 더 많은 콘텐츠 로드
      3.times do |i|
        @driver.execute_script("window.scrollTo(0, document.body.scrollHeight / 4 * #{i + 1});")
        sleep(2)
      end

      # 상품 관련 요소들 찾기
      product_selectors = [
        '.item', '.product', '.goods',  # 일반적인 선택자
        '[class*="item"]', '[class*="product"]', '[class*="goods"]',  # 클래스에 포함된 것들
        'li', 'article',  # HTML 태그 기반
        'a[href*="/products/"]', 'a[href*="/goods/"]'  # 링크 기반
      ]

      all_product_elements = []

      product_selectors.each do |selector|
        begin
          elements = @driver.find_elements(css: selector)
          puts "#{selector}: #{elements.length}개 요소 발견"

          # 상품으로 보이는 요소들 필터링
          elements.each do |element|
            text = element.text.strip
            if text.length > 10 && text.length < 500  # 적절한 길이
              # 가격이나 상품명이 포함되어 있는지 확인
              if text.match(/\d+,?\d*원/) || text.match(/\d+%/) ||
                 text.include?('할인') || text.include?('원')
                all_product_elements << { element: element, text: text, selector: selector }
              end
            end
          end
        rescue => e
          puts "#{selector} 처리 에러: #{e.message}"
          next
        end
      end

      puts "\n총 #{all_product_elements.length}개의 상품 후보 발견"

      # 상위 20개만 처리
      all_product_elements.first(20).each_with_index do |item, index|
        begin
          element = item[:element]
          product = {
            index: index + 1,
            selector_used: item[:selector],
            raw_text: item[:text],
          }

          # 이미지 찾기
          begin
            img = element.find_element(css: 'img')
            product[:image_url] = img.attribute('src') if img
          rescue
            # 이미지 없음
          end

          # 링크 찾기
          begin
            if element.tag_name.downcase == 'a'
              product[:link] = element.attribute('href')
            else
              link = element.find_element(css: 'a')
              product[:link] = link.attribute('href') if link
            end
          rescue
            # 링크 없음
          end

          # 텍스트에서 가격 추출
          price_match = item[:text].match(/(\d+,?\d*원)/)
          product[:price] = price_match[1] if price_match

          # 할인율 추출
          discount_match = item[:text].match(/(\d+%)/)
          product[:discount] = discount_match[1] if discount_match

          products << product

        rescue => e
          puts "상품 #{index + 1} 처리 에러: #{e.message}"
          next
        end
      end

    rescue => e
      puts "상품 목록 추출 에러: #{e.message}"
    end

    products
  end
end

# 사용 예시
if __FILE__ == $0
  crawler = ImprovedSmartStoreCrawler.new(headless: false)

  store_url = "https://smartstore.naver.com/theunitstore"

  puts "=== 개선된 스마트스토어 크롤링 시작 ==="
  result = crawler.crawl_smartstore(store_url)

  if result
    puts "\n=== 크롤링 결과 ==="
    puts "페이지 타이틀: #{result[:page_title]}"
    puts "페이지 URL: #{result[:page_url]}"
    puts "스토어 정보: #{result[:store_info]}"
    puts "상품 수: #{result[:products].length}"

    # JSON 파일로 저장
    filename = "smartstore_improved_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
    File.write(filename, JSON.pretty_generate(result))
    puts "\n결과가 #{filename} 파일로 저장되었습니다."

    # 상품 정보 미리보기
    if result[:products].any?
      puts "\n=== 상품 샘플 ==="
      result[:products].first(5).each do |product|
        puts "#{product[:index]}. #{product[:price]} - #{product[:raw_text][0..50]}..."
      end
    end
  else
    puts "크롤링 실패"
  end
end
