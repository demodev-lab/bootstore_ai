require 'nokogiri'
require 'httparty'
require 'uri'

class NokogiriCrawler
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

  # 기본 크롤링 메소드
  def crawl_url(url)
    puts "크롤링 시작: #{url}"

    begin
      response = HTTParty.get(url, headers: @headers, timeout: 10)

      if response.success?
        doc = Nokogiri::HTML(response.body)
        puts "페이지 로딩 성공! 제목: #{doc.title}"
        return doc
      else
        puts "HTTP 에러: #{response.code}"
        return nil
      end
    rescue => e
      puts "크롤링 실패: #{e.message}"
      return nil
    end
  end

  # 네이버 뉴스 헤드라인 크롤링
  def crawl_naver_news
    puts "\n=== 네이버 뉴스 헤드라인 크롤링 ==="

    url = 'https://news.naver.com/main/home.naver'
    doc = crawl_url(url)
    return unless doc

    # 헤드라인 뉴스 추출
    headlines = []

    # 다양한 셀렉터 시도
    selectors = [
      '.hdline_article_tit',
      '.cjs_news_headline',
      '.cjs_t',
      'a[class*="headline"]',
      '.cluster_text_headline'
    ]

    selectors.each do |selector|
      elements = doc.css(selector)
      if elements.any?
        puts "헤드라인 #{elements.length}개 발견 (#{selector})"
        elements.first(5).each_with_index do |element, index|
          title = element.text.strip
          link = element['href'] || (element.parent['href'] if element.parent)

          if link && !link.start_with?('http')
            link = "https://news.naver.com#{link}"
          end

          headlines << {
            title: title,
            link: link,
            source: '네이버뉴스'
          }

          puts "#{index + 1}. #{title}"
          puts "   링크: #{link}" if link
        end
        break
      end
    end

    return headlines
  end

  # 쿠팡 상품 정보 크롤링 (간단한 예제)
  def crawl_coupang_search(keyword)
    puts "\n=== 쿠팡 검색 결과 크롤링: #{keyword} ==="

    encoded_keyword = URI.encode_www_form_component(keyword)
    url = "https://www.coupang.com/np/search?q=#{encoded_keyword}"

    doc = crawl_url(url)
    return unless doc

    products = []

    # 상품 리스트 추출
    product_elements = doc.css('[data-component-type="s-search-result"]')

    puts "상품 #{product_elements.length}개 발견"

    product_elements.first(5).each_with_index do |product, index|
      name_element = product.css('.name').first
      price_element = product.css('.price-value').first

      name = name_element&.text&.strip
      price = price_element&.text&.strip

      if name && price
        products << {
          name: name,
          price: price,
          source: '쿠팡'
        }

        puts "#{index + 1}. #{name}"
        puts "   가격: #{price}원"
      end
    end

    return products
  end

  # GitHub 트렌딩 저장소 크롤링
  def crawl_github_trending
    puts "\n=== GitHub 트렌딩 저장소 크롤링 ==="

    url = 'https://github.com/trending'
    doc = crawl_url(url)
    return unless doc

    repositories = []

    # 트렌딩 저장소 리스트
    repo_elements = doc.css('article.Box-row')

    puts "트렌딩 저장소 #{repo_elements.length}개 발견"

    repo_elements.first(5).each_with_index do |repo, index|
      name_element = repo.css('h2 a').first
      description_element = repo.css('p').first
      stars_element = repo.css('[href$="/stargazers"]').first
      language_element = repo.css('[itemprop="programmingLanguage"]').first

      if name_element
        name = name_element.text.strip.gsub(/\s+/, ' ')
        description = description_element&.text&.strip
        stars = stars_element&.text&.strip
        language = language_element&.text&.strip

        repositories << {
          name: name,
          description: description,
          stars: stars,
          language: language,
          source: 'GitHub'
        }

        puts "#{index + 1}. #{name}"
        puts "   설명: #{description}" if description
        puts "   언어: #{language}" if language
        puts "   스타: #{stars}" if stars
        puts
      end
    end

    return repositories
  end

  # 특정 웹사이트의 메타 정보 추출
  def extract_meta_info(url)
    puts "\n=== 메타 정보 추출: #{url} ==="

    doc = crawl_url(url)
    return unless doc

    meta_info = {
      title: doc.title,
      description: nil,
      keywords: nil,
      author: nil,
      og_title: nil,
      og_description: nil,
      og_image: nil
    }

    # 메타 태그들 추출
    doc.css('meta').each do |meta|
      name = meta['name']&.downcase
      property = meta['property']&.downcase
      content = meta['content']

      case name
      when 'description'
        meta_info[:description] = content
      when 'keywords'
        meta_info[:keywords] = content
      when 'author'
        meta_info[:author] = content
      end

      case property
      when 'og:title'
        meta_info[:og_title] = content
      when 'og:description'
        meta_info[:og_description] = content
      when 'og:image'
        meta_info[:og_image] = content
      end
    end

    puts "제목: #{meta_info[:title]}"
    puts "설명: #{meta_info[:description]}" if meta_info[:description]
    puts "키워드: #{meta_info[:keywords]}" if meta_info[:keywords]
    puts "작성자: #{meta_info[:author]}" if meta_info[:author]
    puts "OG 제목: #{meta_info[:og_title]}" if meta_info[:og_title]
    puts "OG 설명: #{meta_info[:og_description]}" if meta_info[:og_description]
    puts "OG 이미지: #{meta_info[:og_image]}" if meta_info[:og_image]

    return meta_info
  end

  # 웹사이트의 모든 링크 추출
  def extract_links(url, limit = 10)
    puts "\n=== 링크 추출: #{url} ==="

    doc = crawl_url(url)
    return unless doc

    links = []
    base_uri = URI.parse(url)

    doc.css('a[href]').each do |link|
      href = link['href']
      text = link.text.strip

      # 상대 경로를 절대 경로로 변환
      if href.start_with?('/')
        full_url = "#{base_uri.scheme}://#{base_uri.host}#{href}"
      elsif href.start_with?('http')
        full_url = href
      else
        next # 다른 형태의 링크는 건너뛰기
      end

      links << {
        text: text,
        url: full_url
      }

      break if links.length >= limit
    end

    puts "링크 #{links.length}개 추출:"
    links.each_with_index do |link, index|
      puts "#{index + 1}. #{link[:text]}"
      puts "   #{link[:url]}"
    end

    return links
  end
end

# 사용 예제
if __FILE__ == $0
  crawler = NokogiriCrawler.new

  begin
    # 1. 네이버 뉴스 크롤링
    news = crawler.crawl_naver_news

    # 2. GitHub 트렌딩 크롤링
    repos = crawler.crawl_github_trending

    # 3. 메타 정보 추출 예제
    crawler.extract_meta_info('https://github.com/ruby/ruby')

    # 4. 링크 추출 예제
    crawler.extract_links('https://ruby-lang.org', 5)

    puts "\n=== 크롤링 완료! ==="
    puts "뉴스 #{news&.length || 0}개, 저장소 #{repos&.length || 0}개 수집"

  rescue => e
    puts "실행 중 에러: #{e.message}"
    puts e.backtrace.first(3)
  end
end
