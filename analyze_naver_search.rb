require 'playwright'
require 'json'

puts "Analyzing Naver Smart Store search functionality..."

executable_path = 'npx playwright'

Playwright.create(playwright_cli_executable_path: executable_path) do |playwright|
  browser = playwright.chromium.launch(
    headless: false,
    args: ["--window-size=1920,1080"]
  )
  
  context = browser.new_context(
    viewport: { width: 1920, height: 1080 },
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
  )
  
  page = context.new_page
  
  # Go to a working smart store first
  puts "1. Navigating to a Smart Store..."
  page.goto("https://smartstore.naver.com/funshop", waitUntil: 'networkidle')
  page.wait_for_timeout(3000)
  
  # Look for search functionality
  puts "2. Looking for search functionality..."
  
  # Try to find search input
  search_selectors = [
    'input[type="search"]',
    'input[placeholder*="검색"]',
    'input[name*="search"]',
    'input[name*="query"]',
    'input[class*="search"]',
    '.search input',
    '#search'
  ]
  
  search_input = nil
  search_selectors.each do |selector|
    if page.locator(selector).count > 0
      search_input = page.locator(selector).first
      puts "Found search input with selector: #{selector}"
      break
    end
  end
  
  if search_input
    puts "3. Testing search..."
    search_input.click
    search_input.fill("아이폰 케이스")
    
    # Try to submit search
    page.keyboard.press("Enter")
    page.wait_for_timeout(3000)
    
    puts "4. Current URL after search: #{page.url}"
    puts "   Page title: #{page.title}"
    
    # Analyze search results page
    if page.url.include?("search") || page.url.include?("query")
      puts "\n5. Found search results page!"
      puts "   Search URL pattern: #{page.url}"
      
      # Find result items
      result_selectors = [
        'li[class*="item"]',
        'div[class*="item"]',
        'a[href*="/products/"]',
        '[class*="product"]',
        '[class*="goods"]'
      ]
      
      result_selectors.each do |selector|
        count = page.locator(selector).count
        if count > 0
          puts "   Found #{count} items with selector: #{selector}"
        end
      end
    end
  else
    puts "Could not find search input on the page"
  end
  
  # Alternative: Try searching via URL patterns
  puts "\n6. Testing direct search URLs..."
  search_urls = [
    "https://search.shopping.naver.com/search/all?where=all&frm=SMARTSTORE&query=아이폰케이스",
    "https://smartstore.naver.com/main/search?keyword=아이폰케이스"
  ]
  
  search_urls.each do |url|
    puts "\nTrying: #{url}"
    page.goto(url, waitUntil: 'domcontentloaded')
    page.wait_for_timeout(2000)
    puts "  Response URL: #{page.url}"
    puts "  Title: #{page.title}"
  end
  
  puts "\nKeeping browser open for manual inspection..."
  sleep 30
  
  browser.close
end