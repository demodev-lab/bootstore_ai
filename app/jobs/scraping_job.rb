class ScrapingJob < ApplicationJob
  queue_as :default
  
  retry_on StandardError, wait: 5.minutes, attempts: 3
  
  def perform(store, options = {})
    # Use Playwright scraper for better dynamic content handling
    scraper = PlaywrightStoreScraper.new(store, options)
    result = scraper.scrape
    
    if result[:success]
      Rails.logger.info "Successfully scraped store: #{store.url}"
    else
      Rails.logger.error "Failed to scrape store: #{store.url}, Error: #{result[:error]}"
    end
  end
end