class SmartstoreProductSearcher
  CATEGORY_MAPPINGS = {
    "아이폰" => ["mobilecase", "phoneaccessory", "applestore"],
    "케이스" => ["mobilecase", "phonecase", "casemania"],
    "패션" => ["fashion", "style", "clothing"],
    "뷰티" => ["beauty", "cosmetics", "skincare"],
    "식품" => ["food", "snack", "grocery"],
    "가전" => ["electronics", "appliance", "digital"]
  }.freeze

  POPULAR_STORES = [
    "funshop",
    "mobilecase", 
    "theunitstore",
    "coupang",
    "11st"
  ].freeze

  def self.find_relevant_stores(product_name)
    stores = []
    
    # Find stores based on keywords
    CATEGORY_MAPPINGS.each do |keyword, store_names|
      if product_name.downcase.include?(keyword)
        store_names.each do |store_name|
          stores << "https://smartstore.naver.com/#{store_name}"
        end
      end
    end
    
    # Add some popular general stores if no specific matches
    if stores.empty?
      POPULAR_STORES.first(3).each do |store_name|
        stores << "https://smartstore.naver.com/#{store_name}"
      end
    end
    
    stores.uniq
  end
  
  def self.search_within_store(store_url, product_name)
    # This would use the store's internal search if available
    # For now, we'll browse their product listings
    "#{store_url}/category/ALL?st=POPULAR&dt=IMAGE&page=1&size=40"
  end
end