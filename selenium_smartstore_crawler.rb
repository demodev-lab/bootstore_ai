require 'selenium-webdriver'
require 'nokogiri'
require 'json'

class SeleniumSmartStoreCrawler
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
    @driver.manage.timeouts.implicit_wait = 10
    @driver
  end

  def stop_driver
    @driver&.quit
  end

  def crawl_smartstore(store_url)
    start_driver

    begin
      puts "네이버 스마트스토어 접속: #{store_url}"
      @driver.get(store_url)

      # 페이지 로딩 대기
      sleep(3)

      # JavaScript 실행 완료까지 추가 대기
      wait = Selenium::WebDriver::Wait.new(timeout: 10)
      wait.until { @driver.execute_script("return document.readyState") == "complete" }

      # 상점 기본 정보 수집
      store_info = extract_store_info

      # 상품 목록 수집
      products = extract_products

      # 리뷰 정보 수집 (가능한 경우)
      reviews = extract_reviews

      {
        store_info: store_info,
        products: products,
        reviews: reviews,
        crawled_at: Time.now
      }

    rescue => e
      puts "크롤링 에러: #{e.message}"
      nil
    ensure
      stop_driver
    end
  end

  private

  def extract_store_info
    store_info = {}

    begin
      # 상점명
      store_name = @driver.find_element(css: '.store_name, .seller_name, [data-testid="store-name"]')&.text
      store_info[:name] = store_name if store_name

      # 상점 설명
      store_desc = @driver.find_element(css: '.store_description, .seller_description')&.text
      store_info[:description] = store_desc if store_desc

      # 상점 평점
      rating = @driver.find_element(css: '.rating, .store_rating, [data-testid="rating"]')&.text
      store_info[:rating] = rating if rating

      # 상점 이미지
      store_image = @driver.find_element(css: '.store_logo img, .seller_logo img')&.attribute('src')
      store_info[:image_url] = store_image if store_image

    rescue Selenium::WebDriver::Error::NoSuchElementError => e
      puts "상점 정보 추출 중 일부 요소를 찾을 수 없음: #{e.message}"
    end

    store_info
  end

  def extract_products
    products = []

    begin
      # 상품 목록으로 스크롤 (Lazy Loading 대응)
      scroll_to_load_products

      # 상품 카드들 찾기
      product_elements = @driver.find_elements(css: '.product_item, .item, [data-testid="product-item"]')

      product_elements.each_with_index do |element, index|
        begin
          product = {}

          # 상품명
          name_element = element.find_element(css: '.product_name, .item_name, .name')
          product[:name] = name_element.text if name_element

          # 가격
          price_element = element.find_element(css: '.price, .product_price, .cost')
          product[:price] = price_element.text if price_element

          # 상품 이미지
          img_element = element.find_element(css: 'img')
          product[:image_url] = img_element.attribute('src') if img_element

          # 상품 링크
          link_element = element.find_element(css: 'a')
          product[:product_url] = link_element.attribute('href') if link_element

          # 할인율
          discount_element = element.find_element(css: '.discount, .sale_rate')
          product[:discount] = discount_element.text if discount_element

          # 리뷰 수
          review_count_element = element.find_element(css: '.review_count, .review')
          product[:review_count] = review_count_element.text if review_count_element

          products << product unless product.empty?

        rescue Selenium::WebDriver::Error::NoSuchElementError
          puts "상품 #{index + 1} 정보 추출 중 일부 요소를 찾을 수 없음"
          next
        end
      end

    rescue => e
      puts "상품 목록 추출 에러: #{e.message}"
    end

    products
  end

  def extract_reviews
    reviews = []

    begin
      # 리뷰 섹션으로 이동 시도
      review_button = @driver.find_element(css: '.review_tab, .review_button, [data-testid="review-tab"]')
      @driver.execute_script("arguments[0].click();", review_button) if review_button

      sleep(2)

      # 리뷰 요소들 찾기
      review_elements = @driver.find_elements(css: '.review_item, .review, [data-testid="review-item"]')

      review_elements.first(10).each do |element| # 최대 10개 리뷰만
        begin
          review = {}

          # 리뷰 내용
          content_element = element.find_element(css: '.review_content, .content')
          review[:content] = content_element.text if content_element

          # 평점
          rating_element = element.find_element(css: '.rating, .star_rating')
          review[:rating] = rating_element.text if rating_element

          # 작성자
          author_element = element.find_element(css: '.reviewer, .author')
          review[:author] = author_element.text if author_element

          # 작성일
          date_element = element.find_element(css: '.review_date, .date')
          review[:date] = date_element.text if date_element

          reviews << review unless review.empty?

        rescue Selenium::WebDriver::Error::NoSuchElementError
          next
        end
      end

    rescue => e
      puts "리뷰 추출 에러: #{e.message}"
    end

    reviews
  end

  def scroll_to_load_products
    # 페이지 끝까지 스크롤하여 모든 상품 로딩
    last_height = @driver.execute_script("return document.body.scrollHeight")

    3.times do # 최대 3번 스크롤
      @driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
      sleep(2)

      new_height = @driver.execute_script("return document.body.scrollHeight")
      break if new_height == last_height

      last_height = new_height
    end

    # 다시 상단으로 스크롤
    @driver.execute_script("window.scrollTo(0, 0);")
    sleep(1)
  end
end

# 사용 예시
if __FILE__ == $0
  crawler = SeleniumSmartStoreCrawler.new(headless: false) # headless: true로 백그라운드 실행 가능

  store_url = "https://smartstore.naver.com/theunitstore"

  puts "=== 스마트스토어 크롤링 시작 ==="
  result = crawler.crawl_smartstore(store_url)

  if result
    puts "\n=== 크롤링 결과 ==="
    puts "상점 정보: #{result[:store_info]}"
    puts "상품 수: #{result[:products].length}"
    puts "리뷰 수: #{result[:reviews].length}"

    # JSON 파일로 저장
        File.write("smartstore_data_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json",
               JSON.pretty_generate(result))
    puts "\n결과가 JSON 파일로 저장되었습니다."
  else
    puts "크롤링 실패"
  end
end
