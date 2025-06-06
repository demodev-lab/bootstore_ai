require "selenium-webdriver"
require "nokogiri"
require "httparty"

class NaverStoreScraper
  attr_reader :store_url, :store

  def initialize(store)
    @store = store
    @store_url = store.url
    @options = Selenium::WebDriver::Chrome::Options.new
    @options.add_argument('--headless')  # 백그라운드 실행
    @options.add_argument('--no-sandbox')
    @options.add_argument('--disable-dev-shm-usage')
    @options.add_argument('--disable-gpu')
    @options.add_argument('--window-size=1920,1080')
    @options.add_argument('--user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')

    @driver = nil
  end

  def scrape
    Rails.logger.info "Starting scraping for store: #{@store_url}"
    @store.update!(status: 'scraping')

    begin
      result = perform_scraping

      if result[:success]
        save_scraped_data(result[:data])
        @store.update!(
          status: 'completed',
          scraped_at: Time.current,
          error_message: nil
        )
        { success: true, data: result[:data] }
      else
        handle_scraping_error(result[:error])
        { success: false, error: result[:error] }
      end

    rescue => e
      Rails.logger.error "Scraping failed for #{@store_url}: #{e.message}"
      handle_scraping_error(e.message)
      { success: false, error: e.message }
    ensure
      cleanup
    end
  end

  private

  def start_driver
    # Use explicit ChromeDriver path to avoid version mismatch
    service = Selenium::WebDriver::Service.chrome(path: "/opt/homebrew/bin/chromedriver")
    @driver = Selenium::WebDriver.for :chrome, service: service, options: @options
    @driver.manage.timeouts.implicit_wait = 5
  rescue => e
    Rails.logger.error "Failed to start ChromeDriver: #{e.message}"
    # Fallback to default driver
    @driver = Selenium::WebDriver.for :chrome, options: @options
    @driver.manage.timeouts.implicit_wait = 5
  end

  def cleanup
    @driver&.quit
  end

  def perform_scraping
    start_driver

    Rails.logger.info "Accessing: #{@store_url}"
    @driver.get(@store_url)

    # 페이지 로딩 대기
    sleep(3)
    
    # 상품 페이지로 이동 시도
    begin
      # 전체상품 보기 링크 찾기
      all_products_link = @driver.find_element(css: 'a[href*="/category/ALL"]') ||
                         @driver.find_element(css: 'a[href*="#prd"]') ||
                         @driver.find_element(css: 'a:contains("전체상품")')
                         
      if all_products_link && all_products_link.displayed?
        Rails.logger.info "Clicking all products link"
        all_products_link.click
        sleep(3)
      end
    rescue Selenium::WebDriver::Error::NoSuchElementError
      Rails.logger.info "No all products link found, staying on main page"
    end

    # 스토어 기본 정보 수집
    store_info = extract_store_info

    # 상품 목록 수집
    products_data = extract_products

    {
      success: true,
      data: {
        store_info: store_info,
        products: products_data,
        scraped_at: Time.current
      }
    }

  rescue => e
    { success: false, error: e.message }
  end

  def extract_store_info
    info = {
      name: @store.name,
      url: @store.url
    }

    begin
      # 페이지 타이틀에서 스토어명 추출
      title = @driver.title
      if title && title.length > 0
        info[:name] = title.split('|').first&.strip || title.strip
      end

      # 메타 정보에서 설명 추출
      begin
        meta_desc = @driver.find_element(xpath: "//meta[@name='description']")&.attribute('content')
        info[:description] = meta_desc if meta_desc && meta_desc.length > 0
      rescue Selenium::WebDriver::Error::NoSuchElementError
        # 메타 설명 없음
      end

      # 다양한 선택자로 추가 정보 시도
      ['h1', 'h2', '.title', '.name'].each do |selector|
        begin
          element = @driver.find_element(css: selector)
          if element && element.text.length > 0 && element.text.length < 100
            info[:extracted_name] ||= element.text.strip
            break
          end
        rescue Selenium::WebDriver::Error::NoSuchElementError
          next
        end
      end

    rescue => e
      Rails.logger.error "Error extracting store info: #{e.message}"
    end

    info
  end

  def extract_products
    products = []

    begin
      # 페이지 스크롤하여 더 많은 콘텐츠 로드
      scroll_to_load_products

      # 상품 관련 요소들 찾기
      product_candidates = find_product_elements

      Rails.logger.info "Found #{product_candidates.length} product candidates"

      # 상위 50개만 처리 (너무 많으면 시간 오래 걸림)
      product_candidates.first(50).each_with_index do |item, index|
        begin
          product_data = extract_single_product(item, index)
          products << product_data if product_data
        rescue => e
          Rails.logger.error "Error processing product #{index + 1}: #{e.message}"
          next
        end
      end

    rescue => e
      Rails.logger.error "Error extracting products: #{e.message}"
    end

    products
  end

  def find_product_elements
    product_candidates = []
    
    # 현재 URL 확인
    current_url = @driver.current_url
    Rails.logger.info "Current page URL: #{current_url}"

    # 네이버 스마트스토어 전용 선택자
    selectors = [
      # 2024년 네이버 스마트스토어 선택자  
      'li._2kRKWS_t1E',  # 상품 리스트 아이템 (클래스명 정확히)
      'li.basicList_item__0T9JD',  # 기본 리스트 아이템
      'div.basicList_inner__xCM3J',  # 기본 리스트 내부
      'li[class*="basicList_item"]',  # 기본 리스트 아이템
      'article[class*="product"]',  # 상품 article
      'div[class*="ProductListItem"]',  # 상품 리스트 아이템
      # 대체 선택자  
      'ul > li',  # 일반 리스트 아이템
      'a[href*="/products/"]',  # 상품 링크
      '.item', '.product', '.goods'
    ]

    selectors.each do |selector|
      begin
        elements = @driver.find_elements(css: selector)
        
        # 선택자로 요소를 찾았으면 로그
        if elements.any?
          Rails.logger.info "Found #{elements.length} elements with selector: #{selector}"
        end

        elements.each_with_index do |element, idx|
          text = element.text.strip
          # 상품으로 보이는 조건: 텍스트가 있고 너무 짧거나 길지 않음
          if text.length > 5 && text.length < 2000
            # 가격이 있거나 상품명처럼 보이는 텍스트가 있으면 후보로 추가
            if text.match?(/\d+[만\ucc9c]?\d*원/) || 
               text.match?(/\d{1,3}(,\d{3})*원/) ||
               (text.lines.count > 1 && !text.match?(/^홈$|^전체$/))
               
              # 처음 3개 요소는 로그 출력
              if idx < 3
                Rails.logger.info "Product candidate #{idx + 1} from #{selector}:"
                Rails.logger.info "  Text preview: #{text.lines.first(3).join(' ').strip[0..100]}..."
              end

              product_candidates << {
                element: element,
                text: text,
                selector: selector
              }
            end
          end
        end
      rescue => e
        Rails.logger.error "Error with selector #{selector}: #{e.message}"
        next
      end
    end

    # 중복 제거 (같은 텍스트면 같은 상품으로 간주)
    product_candidates.uniq { |item| item[:text] }
  end

  def extract_single_product(item, index)
    element = item[:element]
    text = item[:text]

    product = {
      name: extract_product_name(text),
      price: extract_price(text),
      discount_rate: extract_discount_rate(text),
      raw_text: text.truncate(500),
      scraped_at: Time.current
    }

    # 이미지 URL 추출
    begin
      img = element.find_element(css: 'img')
      product[:image_url] = img.attribute('src') if img
    rescue
      # 이미지 없음
    end

    # 상품 링크 추출
    begin
      if element.tag_name.downcase == 'a'
        product[:product_url] = element.attribute('href')
      else
        link = element.find_element(css: 'a')
        product[:product_url] = link.attribute('href') if link
      end
    rescue
      # 링크 없음
    end

    # 기본 필드가 있는 경우만 반환
    product if product[:name] || product[:price]
  end

  def extract_product_name(text)
    # 첫 번째 줄이나 가격 앞의 텍스트를 상품명으로 추정
    lines = text.split("\n").map(&:strip).reject(&:empty?)

    lines.each do |line|
      # 가격이나 할인 정보가 아닌 첫 번째 의미있는 줄
      unless line.match?(/\d+,?\d*원/) || line.match?(/\d+%/) || line.include?('할인')
        return line.truncate(255) if line.length > 5
      end
    end

    # 찾지 못하면 전체 텍스트의 첫 부분
    text.split("\n").first&.truncate(255)
  end

  def extract_price(text)
    # 다양한 가격 패턴 처리
    # 1,234,567원 형식
    price_match = text.match(/(\d{1,3}(?:,\d{3})*)원/)
    if price_match
      return price_match[1].gsub(',', '').to_i
    end
    
    # 1234567원 형식
    simple_match = text.match(/(\d+)원/)
    if simple_match
      return simple_match[1].to_i
    end
    
    # 123만4567원 형식
    korean_match = text.match(/(\d+)만\s*(\d*)원/)
    if korean_match
      man = korean_match[1].to_i * 10000
      won = korean_match[2].to_i
      return man + won
    end
    
    nil
  end

  def extract_discount_rate(text)
    discount_match = text.match(/(\d+)%/)
    discount_match ? discount_match[1].to_i : 0
  end

  def scroll_to_load_products
    # 네이버 스마트스토어 상품 탭 클릭 시도
    begin
      # 상품 탭 클릭
      product_tab = @driver.find_element(css: 'a[href*="#prd"]') || 
                    @driver.find_element(css: 'a[href*="/products"]') ||
                    @driver.find_element(css: '[role="tab"]:contains("상품")')
      if product_tab && product_tab.displayed?
        product_tab.click
        sleep(3)
        Rails.logger.info "Clicked product tab"
      end
    rescue Selenium::WebDriver::Error::NoSuchElementError
      Rails.logger.info "No product tab found, continuing with scroll"
    end
    
    # 점진적 스크롤로 Lazy Loading 상품들 로드
    5.times do |i|
      @driver.execute_script("window.scrollTo(0, document.body.scrollHeight / 6 * #{i + 1});")
      sleep(1.5)
    end

    # 맨 위로 다시 스크롤
    @driver.execute_script("window.scrollTo(0, 0);")
    sleep(1)
  end

  def save_scraped_data(data)
    # 스토어 정보 업데이트
    store_info = data[:store_info]
    @store.update!(
      name: store_info[:name] || store_info[:extracted_name] || @store.name,
      description: store_info[:description],
      product_count: data[:products].size,
      average_price: calculate_average_price(data[:products])
    )

    # 기존 상품들 삭제 (최신 데이터로 교체)
    @store.products.destroy_all

    # 새 상품들 저장
    saved_count = 0
    data[:products].each_with_index do |product_data, index|
      next unless product_data[:name] || product_data[:price]

      # URL이 없거나 중복인 경우 고유하게 만들기
      product_url = product_data[:product_url]
      if product_url.blank?
        product_url = "#{@store_url}/product_#{index}_#{Time.current.to_i}"
      end
      
      # find_or_create_by로 중복 처리
      product = @store.products.find_or_initialize_by(product_url: product_url)
      
      product.assign_attributes(
        name: product_data[:name] || '상품명 없음',
        price: product_data[:price] || 0,
        discount_rate: product_data[:discount_rate] || 0,
        image_url: product_data[:image_url],
        raw_data: product_data[:raw_text],
        scraped_at: Time.current
      )
      
      if product.save
        saved_count += 1
      else
        Rails.logger.warn "Failed to save product: #{product.errors.full_messages.join(', ')}"
      end
    end

    Rails.logger.info "Saved #{saved_count} products for store: #{@store.name}"
  end
  
  def calculate_average_price(products)
    prices = products.map { |p| p[:price] }.compact.select { |p| p > 0 }
    return 0 if prices.empty?
    (prices.sum.to_f / prices.size).round(0)
  end

  def handle_scraping_error(error_message)
    @store.update!(
      status: 'failed',
      error_message: error_message.truncate(1000),
      scraped_at: Time.current
    )
  end
end
