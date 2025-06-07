require 'playwright'
require 'json'
require 'cgi'

# Test product name
product_name = "아이폰 케이스"
search_url = "https://smartstore.naver.com/search/all?q=#{CGI.escape(product_name)}"

puts "Testing search URL: #{search_url}"

# Determine playwright executable path
executable_path = [
  ENV['PLAYWRIGHT_CLI_EXECUTABLE_PATH'],
  'npx playwright',
  `which playwright`.strip,
  '/usr/local/bin/playwright',
  '/opt/homebrew/bin/playwright'
].compact.reject(&:empty?).find { |path| 
  path.include?('/') ? File.exist?(path) : system("which #{path} > /dev/null 2>&1")
}

puts "Using Playwright at: #{executable_path}"

Playwright.create(playwright_cli_executable_path: executable_path) do |playwright|
  browser = playwright.chromium.launch(
    headless: false,
    args: [
      "--window-size=1920,1080",
      "--disable-blink-features=AutomationControlled"
    ]
  )
  
  context = browser.new_context(
    viewport: { width: 1920, height: 1080 },
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
  )
  
  page = context.new_page
  
  puts "Navigating to search page..."
  page.goto(search_url, waitUntil: 'networkidle', timeout: 30000)
  
  # Wait for content to load
  page.wait_for_timeout(3000)
  
  puts "\n=== Page Title ==="
  puts page.title
  
  # Try to find search results using various selectors
  selectors_to_test = [
    # Common search result selectors
    'li[class*="item"]',
    'div[class*="searchResult"]',
    'ul[class*="searchResult"] li',
    'div[class*="productList"]',
    'li[class*="productList"]',
    'div[class*="search_list"]',
    'ul[class*="list"] li',
    'div[class*="basicList"]',
    'li[class*="basicList"]',
    # More generic selectors
    'div[class*="item_area"]',
    'div[class*="_item"]',
    'li[class*="_item"]',
    'ul[class*="_list"] li',
    # Naver specific
    'li._itemSection',
    'li.basicList_item__0T9JD',
    'li.subListItem_item__e38_s'
  ]
  
  puts "\n=== Testing Selectors ==="
  selectors_to_test.each do |selector|
    count = page.locator(selector).count
    if count > 0
      puts "✓ #{selector} - Found #{count} elements"
      
      # Get first element's text to verify it's a product
      begin
        first_element = page.locator(selector).first
        text = first_element.text_content.strip[0..100]
        puts "  Sample text: #{text}..."
      rescue
        puts "  (Could not get text)"
      end
    end
  end
  
  # Try to understand the page structure
  puts "\n=== Page Structure Analysis ==="
  
  # Look for main content containers
  main_containers = page.locator('main, [role="main"], #content, .content').all
  puts "Found #{main_containers.size} main containers"
  
  # Look for list containers
  list_containers = page.locator('ul, ol, [role="list"]').all
  puts "Found #{list_containers.size} list containers"
  
  # Try to find product links
  product_links = page.locator('a[href*="/products/"]').all
  puts "Found #{product_links.size} product links"
  
  # Save page HTML for manual inspection
  html_file = "search_page_debug.html"
  File.write(html_file, page.content)
  puts "\nPage HTML saved to: #{html_file}"
  
  # Take a screenshot
  screenshot_file = "search_page_debug.png"
  page.screenshot(path: screenshot_file)
  puts "Screenshot saved to: #{screenshot_file}"
  
  # Interactive debugging - keep browser open
  puts "\n=== Browser will stay open for 30 seconds for inspection ==="
  puts "You can inspect the page manually..."
  sleep 30
  
  browser.close
end

puts "\nDebug session completed!"