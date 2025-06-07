require 'net/http'
require 'uri'
require 'json'
require 'cgi'

# Try different approaches to search products in Naver Smart Store ecosystem
product_name = "아이폰 케이스"

puts "Testing Smart Store search approaches for: #{product_name}\n\n"

# Approach 1: Try Smart Store main page search
puts "1. Testing Smart Store main page..."
uri = URI.parse("https://smartstore.naver.com/")
response = Net::HTTP.get_response(uri)
puts "   Status: #{response.code}"
puts "   Has search form: #{response.body.include?('search')}"

# Approach 2: Try specific smart stores that might have the product
popular_stores = [
  "https://smartstore.naver.com/mobilecase",  # Mobile accessories store
  "https://smartstore.naver.com/phonecasemarket",
  "https://smartstore.naver.com/casemania"
]

puts "\n2. Testing popular stores..."
popular_stores.each do |store_url|
  begin
    uri = URI.parse(store_url)
    response = Net::HTTP.get_response(uri)
    puts "   #{store_url}: #{response.code}"
  rescue => e
    puts "   #{store_url}: Error - #{e.message}"
  end
end

# Approach 3: Try Smart Store category URLs
puts "\n3. Testing category URLs..."
category_urls = [
  "https://smartstore.naver.com/category",
  "https://smartstore.naver.com/best",
  "https://smartstore.naver.com/new"
]

category_urls.each do |url|
  begin
    uri = URI.parse(url)
    response = Net::HTTP.get_response(uri)
    puts "   #{url}: #{response.code}"
  rescue => e
    puts "   #{url}: Error - #{e.message}"
  end
end