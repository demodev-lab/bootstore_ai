require 'playwright'

# Playwright CLI 경로 설정
ENV['PLAYWRIGHT_CLI_EXECUTABLE_PATH'] = '/opt/homebrew/bin/npx'

begin
  puts '=== 네이버 스마트스토어 HTML 구조 분석 ==='

  Playwright.create(playwright_cli_executable_path: '/opt/homebrew/bin/npx') do |playwright|
    browser = playwright.chromium.launch(headless: false)  # 브라우저 창 보기
    page = browser.new_page

    # Navigate to store page
    test_url = 'https://smartstore.naver.com/saramdel'
    puts "페이지 로딩 중: #{test_url}"
    page.goto(test_url)

    # Wait for page to load
    page.wait_for_timeout(5000)

    # 첫 번째 상품 찾기
    product_selectors = [
      'li[class*="basicList"]',
      'div[class*="ProductCard"]',
      'li._2kRKWS_t1E',
      'li.product_item',
      'div[class*="product"]',
      '.item_area'
    ]

    first_product = nil
    product_selectors.each do |selector|
      elements = page.query_selector_all(selector)
      if elements.any?
        first_product = elements.first
        puts "첫 번째 상품 발견 (selector: #{selector})"
        break
      end
    end

    if first_product
      # 상품 요소의 HTML 구조 출력
      html = first_product.inner_html
      puts "\n=== 첫 번째 상품 HTML 구조 ==="
      puts html[0..1000] + "..."

      # 상품명 찾기 시도
      name_selectors = [
        'strong[class*="name"]',
        'a[class*="name"]',
        '.product_name',
        '[class*="title"]',
        'a[class*="link"] strong',
        'a[class*="link"]'
      ]

      puts "\n=== 상품명 찾기 시도 ==="
      name_selectors.each do |selector|
        begin
          element = first_product.query_selector(selector)
          if element
            text = element.text_content.strip
            puts "#{selector}: '#{text}'"
          else
            puts "#{selector}: 요소 없음"
          end
        rescue => e
          puts "#{selector}: 에러 - #{e.message}"
        end
      end

      # 가격 찾기 시도
      price_selectors = [
        'span[class*="price"] em',
        'em[class*="num"]',
        '.price_num',
        '[class*="price"]',
        '.cost_price',
        '.sale_price'
      ]

      puts "\n=== 가격 찾기 시도 ==="
      price_selectors.each do |selector|
        begin
          element = first_product.query_selector(selector)
          if element
            text = element.text_content.strip
            puts "#{selector}: '#{text}'"
          else
            puts "#{selector}: 요소 없음"
          end
        rescue => e
          puts "#{selector}: 에러 - #{e.message}"
        end
      end
    else
      puts "상품을 찾을 수 없습니다."
    end

    # 5초 후 브라우저 닫기
    page.wait_for_timeout(5000)
    browser.close
  end

rescue => e
  puts "에러: #{e.message}"
  puts e.backtrace.first(5)
end
