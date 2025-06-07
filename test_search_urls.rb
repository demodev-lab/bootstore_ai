require 'net/http'
require 'uri'
require 'cgi'

# Test different search URL formats
product_name = "아이폰 케이스"
encoded_name = CGI.escape(product_name)

urls_to_test = [
  "https://smartstore.naver.com/search/all?q=#{encoded_name}",
  "https://search.shopping.naver.com/search/all?query=#{encoded_name}",
  "https://search.shopping.naver.com/search/all?frm=NVSHATC&query=#{encoded_name}",
  "https://shopping.naver.com/search/all?query=#{encoded_name}",
  "https://msearch.shopping.naver.com/search/all?query=#{encoded_name}"
]

puts "Testing search URLs for: #{product_name}\n\n"

urls_to_test.each do |url|
  puts "Testing: #{url}"
  
  begin
    uri = URI.parse(url)
    response = Net::HTTP.get_response(uri)
    
    puts "  Status: #{response.code} #{response.message}"
    puts "  Redirects to: #{response['location']}" if response['location']
    
    # Check if response contains search results
    if response.code == "200"
      body = response.body
      has_products = body.include?("product") || body.include?("상품") || body.include?("item")
      puts "  Contains product data: #{has_products}"
    end
  rescue => e
    puts "  Error: #{e.message}"
  end
  
  puts ""
end