require 'selenium-webdriver'
require 'nokogiri'
require 'httparty'

class NaverStoreScraper
  attr_reader :store_url, :store
  
  def initialize(store)
    @store = store
    @store_url = store.url
  end
  
  def scrape
    begin
      @store.update!(status: 'scraping')
      
      # Set up Selenium WebDriver
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument('--headless')
      options.add_argument('--no-sandbox')
      options.add_argument('--disable-dev-shm-usage')
      options.add_argument('--disable-gpu')
      options.add_argument('--window-size=1920,1080')
      
      driver = Selenium::WebDriver.for :chrome, options: options
      
      # Navigate to store page
      driver.get(@store_url)
      sleep(3) # Wait for page to load
      
      # Extract store name
      store_name = extract_store_name(driver)
      
      # Extract product information
      products_data = extract_products(driver)
      
      # Calculate statistics
      product_count = products_data.size
      average_price = calculate_average_price(products_data)
      business_type = determine_business_type(driver)
      
      # Update store information
      @store.update!(
        name: store_name,
        product_count: product_count,
        average_price: average_price,
        business_type: business_type,
        status: 'completed',
        scraped_at: Time.current
      )
      
      # Save products
      save_products(products_data)
      
      driver.quit
      
      { success: true, message: "Successfully scraped #{product_count} products" }
    rescue StandardError => e
      @store.update!(status: 'failed')
      driver&.quit
      
      { success: false, error: e.message }
    end
  end
  
  private
  
  def extract_store_name(driver)
    begin
      # Try multiple selectors for store name
      selectors = [
        'h1.name',
        '.seller_name',
        'h1._1DbtM',
        'span._3oDjSvLwq9'
      ]
      
      selectors.each do |selector|
        element = driver.find_elements(css: selector).first
        return element.text.strip if element && !element.text.empty?
      end
      
      # Fallback to URL parsing
      @store_url.split('/').last.gsub(/-|_/, ' ').titleize
    rescue
      'Unknown Store'
    end
  end
  
  def extract_products(driver)
    products = []
    
    # Scroll to load more products
    last_height = driver.execute_script("return document.body.scrollHeight")
    
    3.times do
      driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
      sleep(2)
      
      new_height = driver.execute_script("return document.body.scrollHeight")
      break if new_height == last_height
      last_height = new_height
    end
    
    # Extract product elements
    product_elements = driver.find_elements(css: 'li[class*="item"], div[class*="product"]')
    
    product_elements.each_with_index do |element, index|
      begin
        product_data = extract_product_data(element, driver)
        products << product_data if product_data
        
        # Limit to 100 products for initial scraping
        break if index >= 99
      rescue => e
        Rails.logger.error "Error extracting product: #{e.message}"
        next
      end
    end
    
    products
  end
  
  def extract_product_data(element, driver)
    # Extract product name
    name_selectors = ['a[class*="name"]', 'strong[class*="name"]', 'p[class*="name"]']
    name = nil
    
    name_selectors.each do |selector|
      name_element = element.find_elements(css: selector).first
      if name_element && !name_element.text.empty?
        name = name_element.text.strip
        break
      end
    end
    
    return nil unless name
    
    # Extract price
    price_selectors = ['span[class*="price"]', 'em[class*="price"]', 'strong[class*="price"]']
    price = nil
    
    price_selectors.each do |selector|
      price_element = element.find_elements(css: selector).first
      if price_element && !price_element.text.empty?
        price_text = price_element.text.gsub(/[^0-9]/, '')
        price = price_text.to_i if price_text.present?
        break
      end
    end
    
    # Extract product URL
    link_element = element.find_elements(tag_name: 'a').first
    product_url = link_element&.attribute('href')
    
    # Extract image URL
    img_element = element.find_elements(tag_name: 'img').first
    image_url = img_element&.attribute('src')
    
    {
      name: name,
      price: price || 0,
      product_url: product_url,
      image_url: image_url,
      category: 'General' # This could be enhanced with category detection
    }
  end
  
  def calculate_average_price(products_data)
    return 0 if products_data.empty?
    
    prices = products_data.map { |p| p[:price] }.compact.select { |p| p > 0 }
    return 0 if prices.empty?
    
    (prices.sum.to_f / prices.size).round(0)
  end
  
  def determine_business_type(driver)
    page_text = driver.page_source.downcase
    
    if page_text.include?('해외직구') || page_text.include?('overseas') || page_text.include?('import')
      'overseas'
    elsif page_text.include?('국내') || page_text.include?('domestic')
      'domestic'
    else
      'mixed'
    end
  end
  
  def save_products(products_data)
    products_data.each do |product_data|
      next unless product_data[:name].present?
      
      product = @store.products.find_or_initialize_by(
        product_url: product_data[:product_url]
      )
      
      product.update!(
        name: product_data[:name],
        price: product_data[:price],
        image_url: product_data[:image_url],
        category: product_data[:category]
      )
    end
  end
end