# Playwright 기능만 테스트 (DB 저장 없이)
require 'playwright'

# Playwright CLI 경로 설정
ENV['PLAYWRIGHT_CLI_EXECUTABLE_PATH'] = '/opt/homebrew/bin/npx'

begin
  puts '=== Playwright 크롤링 테스트 시작 ==='

  Playwright.create(playwright_cli_executable_path: '/opt/homebrew/bin/npx') do |playwright|
    # Launch browser with optimized settings
    browser = playwright.chromium.launch(
      headless: true,
      args: [
        '--no-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
        '--disable-blink-features=AutomationControlled'
      ]
    )

    # Create new page with custom user agent
    page = browser.new_page(
      user_agent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    )

    # Navigate to store page
    test_url = 'https://smartstore.naver.com/saramdel'
    puts "페이지 로딩 중: #{test_url}"
    page.goto(test_url, wait_until: 'domcontentloaded', timeout: 30000)

    # Wait for page to load
    page.wait_for_timeout(3000)

    # 기본 페이지 정보 확인
    title = page.title
    puts "페이지 제목: #{title}"

    # 스토어 이름 찾기
    selectors = [
      'h1._2wK4wRRrV0',
      'h1.seller_name',
      'h1._1DbtM',
      'span._3oDjSvLwq9',
      '.shop_name',
      'h1[class*="seller"]',
      'h1[class*="store"]'
    ]

    store_name = nil
    selectors.each do |selector|
      begin
        element = page.query_selector(selector)
        if element && !element.text_content.strip.empty?
          store_name = element.text_content.strip
          puts "스토어 이름 발견: #{store_name} (selector: #{selector})"
          break
        end
      rescue => e
        puts "Selector #{selector} 실패: #{e.message}"
      end
    end

    # 상품 찾기
    product_selectors = [
      '._2kRKWS_t1E',  # Main product grid items
      '.product_item',
      '[class*="product"]',
      '.item_area'
    ]

    product_elements = []
    product_selectors.each do |selector|
      elements = page.query_selector_all(selector)
      if elements.any?
        product_elements = elements
        puts "상품 #{elements.length}개 발견 (selector: #{selector})"
        break
      end
    end

    # 첫 번째 상품 정보 확인
    if product_elements.any?
      first_product = product_elements.first

      # 상품명 추출 시도
      name_selectors = [
        'a[class*="name"]',
        '.product_name',
        '[class*="title"]',
        'a[class*="link"]'
      ]

      product_name = nil
      name_selectors.each do |selector|
        begin
          element = first_product.query_selector(selector)
          if element && !element.text_content.strip.empty?
            product_name = element.text_content.strip
            puts "첫 번째 상품명: #{product_name}"
            break
          end
        rescue
          next
        end
      end
    end

    browser.close
    puts '=== Playwright 테스트 성공! ==='
  end

rescue => e
  puts "=== 테스트 실패 ==="
  puts "에러: #{e.message}"
  puts "에러 클래스: #{e.class}"
  puts "에러 백트레이스:"
  puts e.backtrace.first(5)
end
