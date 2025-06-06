require 'nokogiri'
require 'httparty'
require 'json'

class SmartStoreCrawler
  def initialize
    @headers = {
      'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language' => 'ko-KR,ko;q=0.9,en;q=0.8',
      'Accept-Encoding' => 'gzip, deflate, br',
      'Connection' => 'keep-alive',
      'Upgrade-Insecure-Requests' => '1'
    }
  end

  def crawl_store(store_id)
    puts "=== 네이버 스마트스토어 크롤링: #{store_id} ==="

    url = "https://smartstore.naver.com/#{store_id}"

    begin
      response = HTTParty.get(url, headers: @headers, timeout: 15)

      if response.success?
        doc = Nokogiri::HTML(response.body)
        puts "페이지 로딩 성공! 제목: #{doc.title}"

        # 스토어 정보 추출
        store_info = extract_store_info(doc)

        # 상품 정보 추출 시도
        products = extract_products(doc)

        # 결과 출력
        display_results(store_info, products)

        return {
          store_info: store_info,
          products: products
        }
      else
        puts "HTTP 에러: #{response.code}"
        return nil
      end
    rescue => e
      puts "크롤링 실패: #{e.message}"
      return nil
    end
  end

  private

  def extract_store_info(doc)
    puts "\n--- 스토어 정보 추출 중 ---"

    store_info = {
      name: nil,
      description: nil,
      rating: nil,
      review_count: nil
    }

    # 스토어 이름 찾기 시도
    name_selectors = [
      'h1._2wK4wRRrV0',
      'h1.seller_name',
      'h1._1DbtM',
      'h1[class*="seller"]',
      '.shop_name',
      'span._3oDjSvLwq9'
    ]

    name_selectors.each do |selector|
      element = doc.at(selector)
      if element && !element.text.strip.empty?
        store_info[:name] = element.text.strip
        puts "스토어명: #{store_info[:name]} (#{selector})"
        break
      end
    end

    # 평점 정보 찾기
    rating_selectors = [
      '.rating_score',
      '[class*="rating"]',
      '.star_rating'
    ]

    rating_selectors.each do |selector|
      element = doc.at(selector)
      if element && !element.text.strip.empty?
        store_info[:rating] = element.text.strip
        puts "평점: #{store_info[:rating]} (#{selector})"
        break
      end
    end

    return store_info
  end

  def extract_products(doc)
    puts "\n--- 상품 정보 추출 중 ---"

    products = []

    # 다양한 상품 리스트 셀렉터 시도
    product_selectors = [
      '._2kRKWS_t1E',           # 기본 상품 리스트
      'li[class*="basicList"]',  # 기본 리스트 아이템
      '.product_item',           # 상품 아이템
      '[data-testid*="product"]', # 테스트 ID 기반
      'div[class*="product"]'    # 상품 컨테이너
    ]

    product_elements = []
    product_selectors.each do |selector|
      elements = doc.css(selector)
      if elements.any?
        product_elements = elements
        puts "상품 #{elements.length}개 발견 (#{selector})"
        break
      end
    end

    # 상품이 없으면 전체 페이지에서 링크 패턴으로 찾기
    if product_elements.empty?
      puts "기본 셀렉터로 상품을 찾지 못함. 링크 패턴으로 시도..."
      product_links = doc.css('a[href*="/products/"]')
      puts "상품 링크 #{product_links.length}개 발견"

      product_links.first(5).each_with_index do |link, index|
        product_info = {
          name: link.text.strip,
          url: link['href'],
          price: nil,
          image: nil
        }

        # 상대 URL을 절대 URL로 변환
        if product_info[:url].start_with?('/')
          product_info[:url] = "https://smartstore.naver.com#{product_info[:url]}"
        end

        products << product_info
        puts "#{index + 1}. #{product_info[:name]} -> #{product_info[:url]}"
      end
    else
      # 개별 상품 정보 추출
      product_elements.first(5).each_with_index do |product, index|
        product_info = extract_product_details(product)

        if product_info[:name] && !product_info[:name].empty?
          products << product_info
          puts "#{index + 1}. #{product_info[:name]}"
          puts "   가격: #{product_info[:price]}" if product_info[:price]
          puts "   링크: #{product_info[:url]}" if product_info[:url]
        end
      end
    end

    return products
  end

  def extract_product_details(product_element)
    product_info = {
      name: nil,
      price: nil,
      url: nil,
      image: nil
    }

    # 상품명 추출
    name_selectors = [
      'strong[class*="name"]',
      'a[class*="name"]',
      '.product_name',
      '[class*="title"]',
      'a[class*="link"]'
    ]

    name_selectors.each do |selector|
      element = product_element.at(selector)
      if element && !element.text.strip.empty?
        product_info[:name] = element.text.strip

        # 링크도 함께 추출
        if element.name == 'a' && element['href']
          product_info[:url] = element['href']
        end
        break
      end
    end

    # 가격 추출
    price_selectors = [
      'span[class*="price"] em',
      'em[class*="num"]',
      '.price_num',
      '[class*="price"]'
    ]

    price_selectors.each do |selector|
      element = product_element.at(selector)
      if element && !element.text.strip.empty?
        product_info[:price] = element.text.strip
        break
      end
    end

    # 이미지 추출
    img_element = product_element.at('img')
    if img_element && img_element['src']
      product_info[:image] = img_element['src']
    end

    return product_info
  end

  def display_results(store_info, products)
    puts "\n=== 크롤링 결과 ==="
    puts "스토어 이름: #{store_info[:name] || '찾을 수 없음'}"
    puts "평점: #{store_info[:rating] || '찾을 수 없음'}"
    puts "상품 개수: #{products.length}개"

    if products.any?
      puts "\n상품 목록:"
      products.each_with_index do |product, index|
        puts "#{index + 1}. #{product[:name]}"
        puts "   가격: #{product[:price]}" if product[:price]
        puts "   URL: #{product[:url]}" if product[:url]
        puts
      end
    else
      puts "상품 정보를 추출할 수 없었습니다."
      puts "이는 스마트스토어가 JavaScript로 동적 로딩하기 때문일 수 있습니다."
      puts "동적 컨텐츠 크롤링은 Playwright나 Selenium을 사용하는 것이 좋습니다."
    end
  end

  def analyze_page_structure(store_id)
    puts "=== 페이지 구조 분석: #{store_id} ==="

    url = "https://smartstore.naver.com/#{store_id}"
    response = HTTParty.get(url, headers: @headers, timeout: 15)

    if response.success?
      doc = Nokogiri::HTML(response.body)

      puts "페이지 제목: #{doc.title}"
      puts "HTML 길이: #{response.body.length} 문자"

      # JavaScript 관련 요소들 확인
      script_tags = doc.css('script')
      puts "Script 태그 개수: #{script_tags.length}"

      # 주요 컨테이너 확인
      main_containers = doc.css('div[id], div[class*="container"], div[class*="wrapper"]')
      puts "주요 컨테이너 개수: #{main_containers.length}"

      # 가능한 상품 관련 요소들 검색
      possible_product_elements = [
        'div[class*="product"]',
        'li[class*="item"]',
        'div[class*="list"]',
        'div[class*="card"]'
      ]

      puts "\n가능한 상품 요소들:"
      possible_product_elements.each do |selector|
        elements = doc.css(selector)
        puts "#{selector}: #{elements.length}개"
      end
    end
  end
end

# 사용 예제
if __FILE__ == $0
  crawler = SmartStoreCrawler.new

  # 테스트할 스토어 ID들
  test_stores = ['saramdel', 'cj-mart', 'emart']

  test_stores.each do |store_id|
    begin
      result = crawler.crawl_store(store_id)
      puts "\n" + "="*50 + "\n"

      # 페이지 구조도 분석
      crawler.analyze_page_structure(store_id)
      puts "\n" + "="*50 + "\n"

    rescue => e
      puts "#{store_id} 크롤링 실패: #{e.message}"
    end

    sleep(2) # 요청 간격 조절
  end
end
