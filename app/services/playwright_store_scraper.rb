require "playwright"

class PlaywrightStoreScraper
  attr_reader :store_url, :store

  def initialize(store, options = {})
    @store = store
    @store_url = store.url
    @options = options
    @search_mode = options[:search_mode] || false
    @search_query = options[:search_query]
    @all_stores = options[:all_stores] || false
    @filters = options[:filters] || {}
  end

  def scrape
    Rails.logger.info "🚀 Starting Playwright scraping for store: #{@store_url}"
    @store.update!(status: "scraping")

    begin
      result = perform_scraping

      if result[:success]
        save_scraped_data(result[:data])
        @store.update!(
          status: "completed",
          scraped_at: Time.current,
          error_message: nil
        )
        Rails.logger.info "✅ Successfully scraped #{@store.products.count} products"
        { success: true, data: result[:data] }
      else
        handle_scraping_error(result[:error])
        { success: false, error: result[:error] }
      end

    rescue => e
      Rails.logger.error "❌ Scraping failed for #{@store_url}: #{e.message}"
      Rails.logger.error "Error class: #{e.class.name}"
      Rails.logger.error "Full backtrace:"
      e.backtrace.each_with_index do |line, i|
        Rails.logger.error "  #{i}: #{line}"
      end
      handle_scraping_error(e.message)
      { success: false, error: e.message }
    end
  end

  private

  def perform_scraping
    data = {}

    executable_path = find_playwright_executable
    Rails.logger.info "Using Playwright executable: #{executable_path}"

    Playwright.create(playwright_cli_executable_path: executable_path) do |playwright|
      # Launch browser in visible mode (not headless)
      Rails.logger.info "🌐 Launching browser window..."
      browser = playwright.chromium.launch(
        headless: false,  # Show browser window
        args: [
          "--window-size=1920,1080",
          "--disable-blink-features=AutomationControlled",
          "--start-maximized",
          "--disable-web-security",
          "--disable-features=IsolateOrigins,site-per-process",
          "--no-sandbox",
          "--disable-setuid-sandbox"
        ]
      )

      context = browser.new_context(
        viewport: { width: 1920, height: 1080 },
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        extraHTTPHeaders: {
          "Accept-Language" => "ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7",
          "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
          "Accept-Encoding" => "gzip, deflate, br",
          "DNT" => "1",
          "Connection" => "keep-alive",
          "Upgrade-Insecure-Requests" => "1"
        }
      )

      page = context.new_page

      # Add initial script to show automation
      page.add_init_script(script: "console.log('🤖 BoostStoreAI Crawler Started!')")

      # Navigate to store
      Rails.logger.info "📍 Navigating to: #{@store_url}"
      page.goto(@store_url, waitUntil: "networkidle", timeout: 30000)

      # Wait for initial content
      page.wait_for_timeout(3000)

      # Show visual indicator on the page with filter status
      filter_status = @all_stores ? " (전체 타입)" : (@filters.any? { |_, v| v.present? } ? " (필터 적용)" : "")
      indicator_text = @search_mode ? "🔍 BoostStoreAI 상품 검색 중#{filter_status}..." : "🤖 BoostStoreAI 크롤링 중#{filter_status}..."
      page.evaluate("
        const indicator = document.createElement('div');
        indicator.innerHTML = '#{indicator_text}';
        indicator.style.cssText = 'position: fixed; top: 20px; right: 20px; background: #4CAF50; color: white; padding: 10px 20px; border-radius: 5px; font-weight: bold; z-index: 10000; font-size: 14px;';
        document.body.appendChild(indicator);
        setTimeout(() => indicator.remove(), 5000);
      ")

      if @search_mode
        # For search mode, we're searching within a specific store
        Rails.logger.info "🔍 Search mode activated for query: #{@search_query} in store: #{@store_url}"

        # Extract store info as usual
        store_info = extract_store_info(page)
        store_info[:name] = "#{@search_query} 검색 - #{store_info[:name]}"
        filter_desc = @all_stores ? " (전체 타입)" : (@filters.any? { |_, v| v.present? } ? " (필터 적용)" : "")
        store_info[:description] = "#{@search_query} 관련 상품#{filter_desc}"

        # Navigate to products section
        navigate_to_products(page)

        # Extract all products
        all_products = extract_products_with_scroll(page)

        # Filter products that match the search query
        search_terms = @search_query.downcase.split(/\s+/)
        products_data = all_products.select do |product|
          product_text = "#{product[:name]} #{product[:description]}".downcase
          search_terms.any? { |term| product_text.include?(term) }
        end

        # Apply additional filters unless "all_stores" is selected
        unless @all_stores
          products_data = apply_product_filters(products_data)
        end

        Rails.logger.info "🛍️ Found #{products_data.size} products matching '#{@search_query}' out of #{all_products.size} total products"
      else
        # Extract store information
        store_info = extract_store_info(page)

        # Navigate to products section
        navigate_to_products(page)

        # Extract products with dynamic loading
        products_data = extract_products_with_scroll(page)

        # Apply filters unless "all_stores" is selected
        unless @all_stores
          products_data = apply_product_filters(products_data)
        end
      end

      browser.close

      {
        success: true,
        data: {
          store_info: store_info,
          products: products_data,
          scraped_at: Time.current
        }
      }
    end

  rescue => e
    Rails.logger.error "Error in perform_scraping: #{e.message}"
    Rails.logger.error "Error occurred at: #{e.backtrace.first}"
    { success: false, error: e.message }
  end

  def extract_store_info(page)
    info = {
      name: @store.name,
      url: @store.url
    }

    begin
      # Get page title
      title = page.title
      if title && title.length > 0
        info[:name] = title.split("|").first&.strip || title.strip
      end

      # Try to find store name in page
      store_name_selectors = [
        'h1[class*="SellerHeaderTitle"]',
        'span[class*="SellerHeaderTitle"]',
        'h1[class*="seller"]',
        'h1[class*="store"]',
        ".shop_name",
        "h1"
      ]

      store_name_selectors.each do |selector|
        element = page.query_selector(selector)
        if element && element.text_content.strip.length > 0
          info[:name] = element.text_content.strip
          Rails.logger.info "📝 Found store name: #{info[:name]}"
          break
        end
      end

      # Extract description
      begin
        meta_desc = page.query_selector('meta[name="description"]')
        info[:description] = meta_desc.get_attribute("content") if meta_desc
      rescue
        # Continue without description
      end

      # Extract follower count
      follower_selectors = [
        'span[class*="FollowerCount"]',
        '[class*="follower"] em',
        '[class*="follower"]'
      ]

      follower_selectors.each do |selector|
        elements = page.query_selector_all(selector)
        elements.each do |element|
          text = element.text_content.strip
          count_match = text.match(/[\d,]+/)
          if count_match
            info[:follower_count] = count_match[0].gsub(",", "").to_i
            Rails.logger.info "👥 Found follower count: #{info[:follower_count]}"
            break
          end
        end
        break if info[:follower_count]
      end

    rescue => e
      Rails.logger.error "Error extracting store info: #{e.message}"
    end

    info
  end

  def navigate_to_products(page)
    Rails.logger.info "🔍 Looking for products section..."

    # If all_stores option is enabled, try to click "전체" tab first
    if @all_stores
      Rails.logger.info "🌟 All stores mode enabled - looking for '전체' tab..."
      
      begin
        # Try to find and click "전체" tab - specific to Naver SmartStore structure
        all_tab_selectors = [
          # Naver SmartStore category tabs
          'a[class*="category"]:text("전체")',
          'button[class*="category"]:text("전체")',
          'li[class*="category"]:text("전체") a',
          'li[class*="category"]:text("전체") button',
          # Generic tab selectors
          'button:text("전체")',
          'a:text("전체")',
          'li:text("전체") a',
          'li:text("전체") button',
          'div[role="tab"]:text("전체")',
          '[data-tab="전체"]',
          '[data-category="전체"]',
          '[data-filter="전체"]',
          '.tab:text("전체")',
          '.category:text("전체")',
          # Broader search for elements containing "전체"
          '*:text("전체")'
        ]
        
        tab_clicked = false
        all_tab_selectors.each do |selector|
          elements = page.locator(selector)
          if elements.count > 0
            Rails.logger.info "🎯 Found #{elements.count} '전체' elements with selector: #{selector}"
            
            # Try each element until one works
            elements.all.each_with_index do |element, index|
              begin
                if element.is_visible?
                  Rails.logger.info "👆 Clicking '전체' tab (element #{index + 1})"
                  element.click
                  page.wait_for_timeout(3000)
                  tab_clicked = true
                  Rails.logger.info "✅ Successfully clicked '전체' tab"
                  break
                end
              rescue => click_error
                Rails.logger.debug "Click failed for element #{index + 1}: #{click_error.message}"
                next
              end
            end
            
            break if tab_clicked
          end
        end
        
        if !tab_clicked
          Rails.logger.info "⚠️ Could not find clickable '전체' tab, proceeding with default navigation"
        end
      rescue => e
        Rails.logger.debug "Error clicking '전체' tab: #{e.message}"
      end
    end

    # Try different methods to navigate to products
    navigation_methods = [
      # Method 1: Click on "전체상품" link
      lambda do
        # Try different product link selectors
        begin
          # Try "전체상품" link
          if page.locator('a:text("전체상품")').count > 0
            Rails.logger.info "📱 Clicking '전체상품' link"
            page.locator('a:text("전체상품")').first.click
            page.wait_for_timeout(3000)
            return true
          end

          # Try category ALL link
          if page.locator('a[href*="/category/ALL"]').count > 0
            Rails.logger.info "📱 Clicking category ALL link"
            page.locator('a[href*="/category/ALL"]').first.click
            page.wait_for_timeout(3000)
            return true
          end

          # Try "전체보기" link
          if page.locator('a:text("전체보기")').count > 0
            Rails.logger.info "📱 Clicking '전체보기' link"
            page.locator('a:text("전체보기")').first.click
            page.wait_for_timeout(3000)
            return true
          end
        rescue => e
          Rails.logger.debug "Product link navigation failed: #{e.message}"
        end
        false
      end,

      # Method 2: Click on products tab
      lambda do
        begin
          # Try product tab with href
          if page.locator('a[href*="#prd"]').count > 0
            Rails.logger.info "📑 Clicking products tab (href)"
            page.locator('a[href*="#prd"]').first.click
            page.wait_for_timeout(2000)
            return true
          end

          # Try role="tab" with "상품" text
          if page.locator('[role="tab"]:text("상품")').count > 0
            Rails.logger.info "📑 Clicking products tab (role)"
            page.locator('[role="tab"]:text("상품")').first.click
            page.wait_for_timeout(2000)
            return true
          end
        rescue => e
          Rails.logger.debug "Product tab navigation failed: #{e.message}"
        end
        false
      end,

      # Method 3: Navigate directly to products URL
      lambda do
        if @store_url.include?("smartstore.naver.com")
          store_id = @store_url.split("/").last
          products_url = "#{@store_url}/category/ALL"
          Rails.logger.info "🌐 Navigating directly to: #{products_url}"
          page.goto(products_url, waitUntil: "networkidle")
          true
        end
      end
    ]

    # Try each navigation method
    navigation_methods.each do |method|
      begin
        return if method.call
      rescue => e
        Rails.logger.debug "Navigation method failed: #{e.message}"
        next
      end
    end

    Rails.logger.info "⚠️ Could not navigate to products page, staying on current page"
  end

  def extract_products_with_scroll(page)
    products = []
    seen_texts = Set.new

    Rails.logger.info "📜 Starting product extraction with scroll..."

    # Initial scroll to trigger lazy loading
    5.times do |i|
      page.evaluate("window.scrollTo(0, document.body.scrollHeight * #{(i + 1) / 5.0})")
      page.wait_for_timeout(1500)

      # Extract products after each scroll
      new_products = extract_visible_products(page, seen_texts)
      products.concat(new_products)

      Rails.logger.info "📦 Found #{new_products.size} new products (total: #{products.size})"

      # Stop if we have enough products
      break if products.size >= 50
    end

    # Try to load more products if available
    begin
      # Try button version first
      button_locator = page.locator('button:text("더보기")')
      if button_locator.count > 0
        begin
          if button_locator.first.is_visible?
            Rails.logger.info "🔄 Found 'Load More' button, clicking..."
            button_locator.first.click
            page.wait_for_timeout(2000)

            # Extract additional products
            new_products = extract_visible_products(page, seen_texts)
            products.concat(new_products)
          end
        rescue
          # Skip if visibility check fails
        end
      else
        # Try link version
        link_locator = page.locator('a:text("더보기")')
        if link_locator.count > 0
          begin
            if link_locator.first.is_visible?
              Rails.logger.info "🔄 Found 'Load More' link, clicking..."
              link_locator.first.click
              page.wait_for_timeout(2000)

              # Extract additional products
              new_products = extract_visible_products(page, seen_texts)
              products.concat(new_products)
            end
          rescue
            # Skip if visibility check fails
          end
        end
      end
    rescue => e
      Rails.logger.debug "Load more button error: #{e.message}"
    end

    Rails.logger.info "✅ Total products extracted: #{products.size}"
    products
  end

  def extract_visible_products(page, seen_texts)
    products = []

    # Product selectors for Naver Smart Store
    product_selectors = [
      "li.xans-record-",  # Common Cafe24/Naver class
      'li[class*="_2kRKWS"]',  # Product list items
      'li[class*="basicList"]',
      'div[class*="prd_info"]',  # Product info containers
      "ul.prdList > li",  # Product list items
      "div.item_area",  # Item areas
      "li"  # Generic list items as fallback
    ]

    product_selectors.each do |selector|
      elements = page.query_selector_all(selector)

      if elements.any?
        Rails.logger.debug "Found #{elements.size} elements with selector: #{selector}"

        elements.each do |element|
          begin
            # Skip if not visible
            begin
              next unless element.is_visible?
            rescue
              # If visibility check fails, assume it's visible and continue
            end

            text = element.text_content.strip

            # Skip if we've seen this text before (duplicate)
            next if seen_texts.include?(text)

            # Skip if too short or too long
            next if text.length < 5 || text.length > 3000

            # More flexible product detection
            # Check if element contains product-like content
            has_link = element.query_selector('a[href*="/products/"]')
            has_image = element.query_selector("img")
            has_price = text.match?(/\d+[만\ucc9c]?\d*원/) || text.match?(/\d{1,3}(,\d{3})*원/)

            # Consider it a product if it has at least 2 of: link, image, price, or multi-line text
            score = 0
            score += 1 if has_link
            score += 1 if has_image
            score += 1 if has_price
            score += 1 if text.lines.count > 2

            if score >= 2
              product_data = extract_single_product(element, text)

              if product_data && (product_data[:name] || product_data[:price])
                seen_texts.add(text)
                products << product_data

                # Log first few products for debugging
                if products.size <= 3
                  Rails.logger.debug "Product #{products.size}: #{product_data[:name]} - ₩#{product_data[:price]}"
                end
              end
            end
          rescue => e
            Rails.logger.debug "Error processing element: #{e.message}"
            next
          end
        end
      end
    end

    products
  end

  def extract_single_product(element, text)
    product = {
      name: extract_product_name(element, text),
      price: extract_price(text),
      discount_rate: extract_discount_rate(text),
      raw_data: text.truncate(1000),
      scraped_at: Time.current
    }

    # Extract image URL
    begin
      img = element.query_selector("img")
      if img
        product[:image_url] = img.get_attribute("src") || img.get_attribute("data-src")
      end
    rescue
      # Continue without image
    end

    # Extract product URL
    begin
      link = element.query_selector("a")
      if link
        href = link.get_attribute("href")
        product[:product_url] = normalize_url(href) if href
      end
    rescue
      # Continue without URL
    end

    # Extract review count
    review_match = text.match(/리뷰\s*(\d+)/) || text.match(/\((\d+)\)/)
    product[:review_count] = review_match[1].to_i if review_match

    product
  end

  def extract_product_name(element, text)
    # Try to find product name in specific elements
    name_selectors = [
      'p[class*="name"]',
      'strong[class*="title"]',
      'strong[class*="name"]',
      'span[class*="name"]',
      'a[class*="link"] strong',
      "a strong",
      "strong",
      "h3",
      "h4",
      "p"
    ]

    name_selectors.each do |selector|
      name_element = element.query_selector(selector)
      if name_element && name_element.text_content.strip.length > 0
        name = name_element.text_content.strip
        # Skip if it's just a price or percentage
        unless name.match?(/^\d+[만\ucc9c]?\d*원$/) || name.match?(/^\d+%$/)
          return name.truncate(255)
        end
      end
    end

    # Fallback: Use first meaningful line
    lines = text.split("\n").map(&:strip).reject(&:empty?)
    lines.each do |line|
      # Skip price-only lines, percentage-only lines, or very short lines
      unless line.match?(/^\d+[만\ucc9c]?\d*원$/) || line.match?(/^\d+%$/) || line.length < 3
        return line.truncate(255)
      end
    end

    # Last resort: return first line if exists
    lines.first&.truncate(255)
  end

  def extract_price(text)
    # Handle various price formats
    # 1,234,567원
    if match = text.match(/(\d{1,3}(?:,\d{3})*)\s*원/)
      return match[1].gsub(",", "").to_i
    end

    # 1234567원
    if match = text.match(/(\d+)\s*원/)
      return match[1].to_i
    end

    # 123만4567원
    if match = text.match(/(\d+)\s*만\s*(\d*)\s*원/)
      man = match[1].to_i * 10000
      won = match[2].to_i
      return man + won
    end

    0
  end

  def extract_discount_rate(text)
    match = text.match(/(\d+)\s*%/)
    match ? match[1].to_i : 0
  end

  def normalize_url(url)
    return nil unless url

    if url.start_with?("//")
      "https:#{url}"
    elsif url.start_with?("/")
      "https://smartstore.naver.com#{url}"
    else
      url
    end
  end

  def save_scraped_data(data)
    # Update store information
    store_info = data[:store_info]
    @store.update!(
      name: store_info[:name] || @store.name,
      description: store_info[:description],
      follower_count: store_info[:follower_count] || 0,
      product_count: data[:products].size,
      average_price: calculate_average_price(data[:products])
    )

    # Clear existing products
    @store.products.destroy_all

    # Save new products
    saved_count = 0
    data[:products].each_with_index do |product_data, index|
      next unless product_data[:name] || product_data[:price]

      # Generate unique URL if missing
      product_url = product_data[:product_url]
      if product_url.blank?
        product_url = "#{@store_url}/product_#{index}_#{Time.current.to_i}"
      end

      # Use find_or_initialize_by to handle duplicates
      product = @store.products.find_or_initialize_by(product_url: product_url)

      product.assign_attributes(
        name: product_data[:name] || "상품 #{index + 1}",
        price: product_data[:price] || 0,
        discount_rate: product_data[:discount_rate] || 0,
        review_count: product_data[:review_count] || 0,
        image_url: product_data[:image_url],
        raw_data: product_data[:raw_data],
        scraped_at: Time.current,
        category: determine_category(product_data[:name])
      )

      if product.save
        saved_count += 1
      else
        Rails.logger.warn "Failed to save product: #{product.errors.full_messages.join(', ')}"
      end
    end

    Rails.logger.info "💾 Saved #{saved_count} products for store: #{@store.name}"
  end

  def calculate_average_price(products)
    prices = products.map { |p| p[:price] }.compact.select { |p| p > 0 }
    return 0 if prices.empty?
    (prices.sum.to_f / prices.size).round(0)
  end

  def determine_category(product_name)
    return "General" unless product_name

    categories = {
      "패션" => %w[옷 의류 셔츠 바지 드레스 스커트 재킷 코트 신발 가방 액세서리],
      "뷰티" => %w[화장품 스킨케어 메이크업 향수 클렌징 마스크],
      "생활" => %w[세제 청소 수납 정리 주방 욕실 침구],
      "식품" => %w[음식 간식 음료 차 커피 쌀 반찬 과일],
      "전자" => %w[전자 가전 스마트 충전기 케이블 이어폰],
      "스포츠" => %w[운동 스포츠 헬스 요가 수영 등산],
      "건강" => %w[건강 영양제 비타민 다이어트 의료]
    }

    name_lower = product_name.downcase

    categories.each do |category, keywords|
      return category if keywords.any? { |keyword| name_lower.include?(keyword) }
    end

    "General"
  end

  def handle_scraping_error(error_message)
    @store.update!(
      status: "failed",
      error_message: error_message.truncate(1000),
      scraped_at: Time.current
    )
  end

  def extract_search_results(page)
    products = []
    seen_texts = Set.new

    Rails.logger.info "🔍 Extracting search results for: #{@search_query}"

    # Wait for search results to load with various selectors
    wait_selectors = [
      'li[class*="basicList_item"]',
      'div[class*="basicList"]',
      'ul[class*="list"] li',
      "#__next",
      "main"
    ]

    loaded = false
    wait_selectors.each do |selector|
      begin
        page.wait_for_selector(selector, timeout: 5000)
        loaded = true
        Rails.logger.info "Page loaded with selector: #{selector}"
        break
      rescue
        next
      end
    end

    unless loaded
      Rails.logger.warn "Could not detect page load, continuing anyway..."
    end

    # Add delay to ensure content is rendered
    page.wait_for_timeout(3000)

    # Scroll to load more results
    5.times do |i|
      page.evaluate("window.scrollTo(0, document.body.scrollHeight * #{(i + 1) / 5.0})")
      page.wait_for_timeout(1500)
    end

    # Search result selectors for Naver Shopping
    search_result_selectors = [
      "li.basicList_item__0T9JD",  # Current Naver Shopping selector
      'li[class*="basicList_item"]',  # Pattern match
      "div.adProduct_item__UKZ_V",  # Ad products
      'li[class*="productList"]',
      'div[class*="product_item"]',
      'li[class*="item"]',
      'article[class*="product"]',
      "li"  # Fallback
    ]

    search_result_selectors.each do |selector|
      elements = page.query_selector_all(selector)

      if elements.any?
        Rails.logger.debug "Found #{elements.size} search results with selector: #{selector}"

        elements.each do |element|
          begin
            # Check if element is visible
            begin
              next unless element.is_visible?
            rescue
              # Continue if visibility check fails
            end

            text = element.text_content.strip

            # Skip duplicates
            next if seen_texts.include?(text)
            next if text.length < 10 || text.length > 3000

            # Extract product data from search result
            product_data = extract_search_result_product(element, text)

            if product_data && product_data[:name]
              seen_texts.add(text)
              products << product_data

              # Log first few products
              if products.size <= 5
                Rails.logger.info "Search result #{products.size}: #{product_data[:name]} - ₩#{product_data[:price]}"
              end
            end

            # Stop after collecting enough products
            break if products.size >= 100
          rescue => e
            Rails.logger.debug "Error processing search result: #{e.message}"
            next
          end
        end
      end

      break if products.size >= 50
    end

    Rails.logger.info "✅ Extracted #{products.size} products from search results"
    products
  end

  def extract_search_result_product(element, text)
    product = {
      name: nil,
      price: extract_price(text),
      discount_rate: extract_discount_rate(text),
      raw_data: text.truncate(1000),
      scraped_at: Time.current
    }

    # Extract product name from search result - Updated for Naver Shopping
    name_selectors = [
      "div.basicList_title__VfX3c",  # Naver Shopping title
      "a.basicList_link__JLQJf",  # Product link text
      'div[class*="title"]',
      'a[class*="link"]',
      'strong[class*="name"]',
      'span[class*="name"]',
      'a[class*="tit"]',
      "strong",
      "a"
    ]

    name_selectors.each do |selector|
      name_element = element.query_selector(selector)
      if name_element
        name_text = name_element.text_content.strip
        unless name_text.match?(/^\d+[만천]?\d*원$/) || name_text.match?(/^\d+%$/) || name_text.length < 3
          product[:name] = name_text.truncate(255)
          break
        end
      end
    end

    # Fallback: extract from text
    if product[:name].nil?
      lines = text.split("\n").map(&:strip).reject(&:empty?)
      lines.each do |line|
        unless line.match?(/^\d+[만천]?\d*원$/) || line.match?(/^\d+%$/) || line.length < 3
          product[:name] = line.truncate(255)
          break
        end
      end
    end

    # Extract store name (for search results)
    store_selectors = [
      "a.basicList_mall__BC5Xu",  # Naver Shopping mall name
      "div.basicList_mall_area__faH62",  # Mall area
      'a[class*="mall"]',
      'span[class*="mall"]',
      'a[class*="store"]',
      'span[class*="store"]'
    ]

    store_selectors.each do |selector|
      store_element = element.query_selector(selector)
      if store_element
        product[:store_name] = store_element.text_content.strip
        break
      end
    end

    # Extract image URL
    begin
      img = element.query_selector("img")
      if img
        product[:image_url] = img.get_attribute("src") || img.get_attribute("data-src")
      end
    rescue
      # Continue without image
    end

    # Extract product URL
    begin
      link = element.query_selector('a[href*="/products/"]') || element.query_selector("a")
      if link
        href = link.get_attribute("href")
        product[:product_url] = normalize_url(href) if href
      end
    rescue
      # Continue without URL
    end

    # Extract review count
    review_match = text.match(/리뷰\s*(\d+)/) || text.match(/\((\d+)\)/)
    product[:review_count] = review_match[1].to_i if review_match

    product
  end

  def apply_product_filters(products)
    return products if @filters.empty?

    filtered_products = products

    # Apply price range filter
    if @filters[:price_min].present? && @filters[:price_min].to_i > 0
      min_price = @filters[:price_min].to_i
      filtered_products = filtered_products.select { |p| p[:price] && p[:price] >= min_price }
    end

    if @filters[:price_max].present? && @filters[:price_max].to_i > 0
      max_price = @filters[:price_max].to_i
      filtered_products = filtered_products.select { |p| p[:price] && p[:price] <= max_price }
    end

    # Note: min_products filter is applied at the store level in the controller
    # overseas filter is also applied at the store level

    Rails.logger.info "🔸 Applied filters: #{@filters.inspect} - Products: #{products.size} → #{filtered_products.size}"

    filtered_products
  end

  def find_playwright_executable
    # Try multiple methods to find Playwright
    paths = [
      ENV["PLAYWRIGHT_CLI_EXECUTABLE_PATH"],
      "npx playwright",
      `which playwright`.strip,
      "/usr/local/bin/playwright",
      "/opt/homebrew/bin/playwright",
      Rails.root.join("node_modules/.bin/playwright").to_s
    ].compact.reject(&:empty?)

    # Find the first existing path
    found_path = paths.find do |path|
      if path.include?("/")
        File.exist?(path)
      else
        system("which #{path} > /dev/null 2>&1")
      end
    end

    found_path || "/opt/homebrew/bin/playwright"
  end
end
