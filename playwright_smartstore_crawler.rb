require 'playwright'
require 'json'

class PlaywrightSmartStoreCrawler
  def initialize(headless: true)
    @headless = headless
    @playwright = nil
    @browser = nil
    @page = nil
  end

      def start_browser
    Playwright.create(playwright_cli_executable_path: './node_modules/.bin/playwright') do |playwright|
      @playwright = playwright
      @browser = playwright.chromium.launch(
        headless: @headless,
        args: [
          '--no-sandbox',
          '--disable-dev-shm-usage',
          '--disable-gpu'
        ]
      )

      @page = @browser.new_page
      @page.set_viewport_size(width: 1920, height: 1080)
      @page.set_extra_http_headers({
        'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      })
    end

    @page
  end

  def close_browser
    @browser&.close
    @playwright&.stop
  end

  def crawl_smartstore(store_url)
    start_browser

    begin
      puts "네이버 스마트스토어 접속: #{store_url}"
      @page.goto(store_url, wait_until: 'networkidle')

      # 추가 JavaScript 로딩 대기
      @page.wait_for_timeout(3000)

      # 상점 기본 정보 수집
      store_info = extract_store_info

      # 상품 목록 수집
      products = extract_products

      # 리뷰 정보 수집
      reviews = extract_reviews

      {
        store_info: store_info,
        products: products,
        reviews: reviews,
        crawled_at: Time.current
      }

    rescue => e
      puts "크롤링 에러: #{e.message}"
      puts e.backtrace
      nil
    ensure
      close_browser
    end
  end

  private

  def extract_store_info
    store_info = {}

    begin
      # 상점명 추출 (여러 선택자 시도)
      store_name_selectors = [
        '.seller_name',
        '.store_name',
        '[data-testid="store-name"]',
        '.smartstore_name',
        '.store_info .name'
      ]

      store_name_selectors.each do |selector|
        if @page.query_selector(selector)
          store_info[:name] = @page.text_content(selector).strip
          break
        end
      end

      # 상점 설명
      desc_selectors = ['.store_description', '.seller_description', '.store_intro']
      desc_selectors.each do |selector|
        if @page.query_selector(selector)
          store_info[:description] = @page.text_content(selector).strip
          break
        end
      end

      # 상점 평점
      rating_selectors = ['.rating', '.store_rating', '.review_score']
      rating_selectors.each do |selector|
        if @page.query_selector(selector)
          store_info[:rating] = @page.text_content(selector).strip
          break
        end
      end

      # 상점 로고/이미지
      img_selectors = ['.store_logo img', '.seller_logo img', '.store_image img']
      img_selectors.each do |selector|
        if @page.query_selector(selector)
          store_info[:image_url] = @page.get_attribute(selector, 'src')
          break
        end
      end

    rescue => e
      puts "상점 정보 추출 에러: #{e.message}"
    end

    store_info
  end

  def extract_products
    products = []

    begin
      # 페이지 스크롤하여 모든 상품 로딩
      scroll_to_load_products

      # 상품 요소들 찾기
      product_selectors = [
        '.product_item',
        '.item',
        '.goods_item',
        '[data-testid="product-item"]',
        '.list_product .item'
      ]

      product_elements = nil
      product_selectors.each do |selector|
        product_elements = @page.query_selector_all(selector)
        break if product_elements.any?
      end

      if product_elements.nil? || product_elements.empty?
        puts "상품 요소를 찾을 수 없습니다."
        return products
      end

      puts "#{product_elements.length}개의 상품을 발견했습니다."

      product_elements.first(20).each_with_index do |element, index|
        begin
          product = {}

          # 상품명
          name_selectors = ['.product_name', '.item_name', '.name', '.goods_name']
          name_selectors.each do |selector|
            name_element = element.query_selector(selector)
            if name_element
              product[:name] = name_element.text_content.strip
              break
            end
          end

          # 가격
          price_selectors = ['.price', '.product_price', '.cost', '.goods_price']
          price_selectors.each do |selector|
            price_element = element.query_selector(selector)
            if price_element
              product[:price] = price_element.text_content.strip
              break
            end
          end

          # 상품 이미지
          img_element = element.query_selector('img')
          if img_element
            product[:image_url] = img_element.get_attribute('src')
          end

          # 상품 링크
          link_element = element.query_selector('a')
          if link_element
            href = link_element.get_attribute('href')
            product[:product_url] = href&.start_with?('http') ? href : "https://smartstore.naver.com#{href}"
          end

          # 할인율
          discount_selectors = ['.discount', '.sale_rate', '.discount_rate']
          discount_selectors.each do |selector|
            discount_element = element.query_selector(selector)
            if discount_element
              product[:discount] = discount_element.text_content.strip
              break
            end
          end

          # 리뷰 수
          review_selectors = ['.review_count', '.review', '.review_cnt']
          review_selectors.each do |selector|
            review_element = element.query_selector(selector)
            if review_element
              product[:review_count] = review_element.text_content.strip
              break
            end
          end

          products << product unless product.empty?

        rescue => e
          puts "상품 #{index + 1} 정보 추출 에러: #{e.message}"
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
      # 리뷰 탭 클릭 시도
      review_tab_selectors = [
        '.review_tab',
        '.review_button',
        '[data-testid="review-tab"]',
        'button:has-text("리뷰")',
        'a:has-text("리뷰")'
      ]

      review_tab_selectors.each do |selector|
        if @page.query_selector(selector)
          @page.click(selector)
          @page.wait_for_timeout(2000)
          break
        end
      end

      # 리뷰 요소들 찾기
      review_selectors = ['.review_item', '.review', '[data-testid="review-item"]', '.review_list .item']

      review_elements = nil
      review_selectors.each do |selector|
        review_elements = @page.query_selector_all(selector)
        break if review_elements.any?
      end

      return reviews if review_elements.nil? || review_elements.empty?

      review_elements.first(10).each do |element|
        begin
          review = {}

          # 리뷰 내용
          content_selectors = ['.review_content', '.content', '.review_text']
          content_selectors.each do |selector|
            content_element = element.query_selector(selector)
            if content_element
              review[:content] = content_element.text_content.strip
              break
            end
          end

          # 평점
          rating_selectors = ['.rating', '.star_rating', '.review_rating']
          rating_selectors.each do |selector|
            rating_element = element.query_selector(selector)
            if rating_element
              review[:rating] = rating_element.text_content.strip
              break
            end
          end

          # 작성자
          author_selectors = ['.reviewer', '.author', '.review_author']
          author_selectors.each do |selector|
            author_element = element.query_selector(selector)
            if author_element
              review[:author] = author_element.text_content.strip
              break
            end
          end

          # 작성일
          date_selectors = ['.review_date', '.date', '.review_time']
          date_selectors.each do |selector|
            date_element = element.query_selector(selector)
            if date_element
              review[:date] = date_element.text_content.strip
              break
            end
          end

          reviews << review unless review.empty?

        rescue => e
          puts "리뷰 추출 에러: #{e.message}"
          next
        end
      end

    rescue => e
      puts "리뷰 섹션 접근 에러: #{e.message}"
    end

    reviews
  end

  def scroll_to_load_products
    # 점진적 스크롤로 Lazy Loading 상품들 로드
    previous_height = 0
    current_height = @page.evaluate("document.body.scrollHeight")

    while previous_height != current_height
      previous_height = current_height

      # 페이지 끝까지 스크롤
      @page.evaluate("window.scrollTo(0, document.body.scrollHeight)")
      @page.wait_for_timeout(2000)

      current_height = @page.evaluate("document.body.scrollHeight")
    end

    # 다시 상단으로 스크롤
    @page.evaluate("window.scrollTo(0, 0)")
    @page.wait_for_timeout(1000)
  end
end

# 사용 예시
if __FILE__ == $0
  crawler = PlaywrightSmartStoreCrawler.new(headless: false) # headless: true로 백그라운드 실행

  store_url = "https://smartstore.naver.com/theunitstore"

  puts "=== Playwright 스마트스토어 크롤링 시작 ==="
  result = crawler.crawl_smartstore(store_url)

  if result
    puts "\n=== 크롤링 결과 ==="
    puts "상점 정보: #{result[:store_info]}"
    puts "상품 수: #{result[:products].length}"
    puts "리뷰 수: #{result[:reviews].length}"

    # JSON 파일로 저장
    filename = "smartstore_playwright_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
    File.write(filename, JSON.pretty_generate(result))
    puts "\n결과가 #{filename} 파일로 저장되었습니다."

    # 상품 정보 미리보기
    if result[:products].any?
      puts "\n=== 상품 샘플 ==="
      result[:products].first(3).each_with_index do |product, index|
        puts "#{index + 1}. #{product[:name]} - #{product[:price]}"
      end
    end
  else
    puts "크롤링 실패"
  end
end
