require 'playwright'

product_name = "아이폰 케이스"
search_url = "https://search.shopping.naver.com/search/all?where=all&frm=NVSHATC&query=#{CGI.escape(product_name)}"

puts "Testing Naver Shopping search page: #{search_url}"

executable_path = 'npx playwright'

Playwright.create(playwright_cli_executable_path: executable_path) do |playwright|
  browser = playwright.chromium.launch(
    headless: false,
    args: ["--window-size=1920,1080"]
  )
  
  context = browser.new_context(
    viewport: { width: 1920, height: 1080 },
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
  )
  
  page = context.new_page
  
  puts "Navigating to search page..."
  page.goto(search_url, waitUntil: 'networkidle')
  page.wait_for_timeout(5000)
  
  puts "\nPage Title: #{page.title}"
  puts "Current URL: #{page.url}"
  
  # Test various selectors
  selectors = {
    # Naver Shopping specific selectors
    'li.basicList_item__0T9JD' => 'Basic list items',
    'div.basicList_inner__xCM3J' => 'Inner product containers',
    'a.basicList_link__JLQJf' => 'Product links',
    'div.basicList_title__VfX3c' => 'Product titles',
    'span.price_num__S2p_v' => 'Prices',
    'div.basicList_mall__BC5Xu' => 'Store names',
    # Alternative selectors
    'li[class*="basicList_item"]' => 'List items (pattern)',
    'div[class*="product_title"]' => 'Product titles (pattern)',
    'a[class*="product_link"]' => 'Product links (pattern)',
    '[class*="price"]' => 'Price elements',
    # Generic selectors
    'li[class*="item"]' => 'Generic items',
    'a[href*="/products/"]' => 'Product URLs',
    'img[class*="thumbnail"]' => 'Product images'
  }
  
  puts "\n=== Testing Selectors ==="
  selectors.each do |selector, description|
    count = page.locator(selector).count
    if count > 0
      puts "✓ #{selector} (#{description}): #{count} elements"
      
      # Get sample data from first element
      begin
        element = page.locator(selector).first
        if selector.include?('title') || selector.include?('link')
          text = element.text_content.strip[0..80]
          puts "  Sample: #{text}..."
        elsif selector.include?('price')
          text = element.text_content.strip
          puts "  Sample price: #{text}"
        end
      rescue
        # Skip if can't get text
      end
    end
  end
  
  # Extract structured data from first product
  puts "\n=== First Product Data ==="
  begin
    first_item = page.locator('li.basicList_item__0T9JD').first
    if first_item
      # Title
      title_elem = first_item.locator('div.basicList_title__VfX3c').first
      title = title_elem ? title_elem.text_content.strip : 'N/A'
      puts "Title: #{title}"
      
      # Price
      price_elem = first_item.locator('span.price_num__S2p_v').first
      price = price_elem ? price_elem.text_content.strip : 'N/A'
      puts "Price: #{price}"
      
      # Store
      store_elem = first_item.locator('a.basicList_mall__BC5Xu').first
      store = store_elem ? store_elem.text_content.strip : 'N/A'
      puts "Store: #{store}"
      
      # Link
      link_elem = first_item.locator('a.basicList_link__JLQJf').first
      href = link_elem ? link_elem.get_attribute('href') : 'N/A'
      puts "Link: #{href}"
      
      # Image
      img_elem = first_item.locator('img').first
      img_src = img_elem ? img_elem.get_attribute('src') : 'N/A'
      puts "Image: #{img_src}"
    end
  rescue => e
    puts "Error extracting product data: #{e.message}"
  end
  
  # Save screenshot
  page.screenshot(path: 'naver_shopping_search.png')
  puts "\nScreenshot saved to naver_shopping_search.png"
  
  puts "\nBrowser will remain open for 30 seconds..."
  sleep 30
  
  browser.close
end