require 'nokogiri'
require 'httparty'

puts "=== Nokogiri 실용적인 크롤링 예제 ==="

class SimpleNokogiriExamples
  def initialize
    @headers = {
      'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    }
  end

  # 1. 한국 날씨 정보 크롤링 (기상청)
  def crawl_weather
    puts "\n=== 기상청 날씨 정보 크롤링 ==="

    url = 'https://www.weather.go.kr/w/weather/forecast/short-term.do'

    begin
      response = HTTParty.get(url, headers: @headers, timeout: 10)

      if response.success?
        doc = Nokogiri::HTML(response.body)
        puts "페이지 제목: #{doc.title}"

        # 날씨 정보 추출 시도 (실제 셀렉터는 페이지 구조에 따라 다를 수 있음)
        weather_elements = doc.css('.weather-item, .forecast-item, [class*="weather"]').first(3)

        if weather_elements.any?
          puts "날씨 정보:"
          weather_elements.each_with_index do |element, index|
            puts "#{index + 1}. #{element.text.strip}"
          end
        else
          puts "날씨 정보를 찾을 수 없습니다."
        end
      else
        puts "날씨 정보 크롤링 실패: HTTP #{response.code}"
      end
    rescue => e
      puts "날씨 크롤링 에러: #{e.message}"
    end
  end

  # 2. 네이버 실시간 검색어 (가능한 경우)
  def crawl_naver_trends
    puts "\n=== 네이버 메인 페이지 정보 ==="

    url = 'https://www.naver.com'

    begin
      response = HTTParty.get(url, headers: @headers, timeout: 10)

      if response.success?
        doc = Nokogiri::HTML(response.body)
        puts "페이지 제목: #{doc.title}"

        # 메인 링크들 추출
        main_links = doc.css('a[href]').select { |link|
          !link.text.strip.empty? && link.text.strip.length > 2
        }.first(10)

        puts "주요 링크들:"
        main_links.each_with_index do |link, index|
          puts "#{index + 1}. #{link.text.strip}"
        end
      else
        puts "네이버 크롤링 실패: HTTP #{response.code}"
      end
    rescue => e
      puts "네이버 크롤링 에러: #{e.message}"
    end
  end

  # 3. Ruby 공식 사이트 정보
  def crawl_ruby_site
    puts "\n=== Ruby 공식 사이트 정보 ==="

    url = 'https://www.ruby-lang.org/ko/'

    begin
      response = HTTParty.get(url, headers: @headers, timeout: 10)

      if response.success?
        doc = Nokogiri::HTML(response.body)
        puts "페이지 제목: #{doc.title}"

        # 메인 헤딩들 추출
        headings = doc.css('h1, h2, h3').first(5)
        puts "주요 제목들:"
        headings.each_with_index do |heading, index|
          puts "#{index + 1}. #{heading.name.upcase}: #{heading.text.strip}"
        end

        # 뉴스나 업데이트 정보 찾기
        news_elements = doc.css('[class*="news"], [class*="update"], .post, article').first(3)
        if news_elements.any?
          puts "\n최신 정보:"
          news_elements.each_with_index do |news, index|
            text = news.text.strip[0..100] + "..." if news.text.strip.length > 100
            puts "#{index + 1}. #{text || news.text.strip}"
          end
        end

      else
        puts "Ruby 사이트 크롤링 실패: HTTP #{response.code}"
      end
    rescue => e
      puts "Ruby 사이트 크롤링 에러: #{e.message}"
    end
  end

  # 4. 정적 HTML 분석 예제
  def analyze_html_structure(url)
    puts "\n=== HTML 구조 분석: #{url} ==="

    begin
      response = HTTParty.get(url, headers: @headers, timeout: 10)

      if response.success?
        doc = Nokogiri::HTML(response.body)

        puts "페이지 정보:"
        puts "- 제목: #{doc.title}"
        puts "- HTML 크기: #{response.body.length} bytes"

        # 태그 통계
        tag_counts = {}
        doc.css('*').each do |element|
          tag_counts[element.name] = (tag_counts[element.name] || 0) + 1
        end

        puts "- 주요 태그 개수:"
        tag_counts.sort_by { |k, v| -v }.first(8).each do |tag, count|
          puts "  #{tag}: #{count}개"
        end

        # 메타 정보
        description = doc.at('meta[name="description"]')
        keywords = doc.at('meta[name="keywords"]')

        puts "- 메타 정보:"
        puts "  설명: #{description['content']}" if description
        puts "  키워드: #{keywords['content']}" if keywords

        # 이미지 개수
        images = doc.css('img')
        puts "- 이미지 개수: #{images.length}개"

        # 링크 개수
        links = doc.css('a[href]')
        puts "- 링크 개수: #{links.length}개"

      else
        puts "분석 실패: HTTP #{response.code}"
      end
    rescue => e
      puts "분석 에러: #{e.message}"
    end
  end

  # 5. 텍스트 추출 및 정리
  def extract_clean_text(url, limit = 500)
    puts "\n=== 텍스트 추출: #{url} ==="

    begin
      response = HTTParty.get(url, headers: @headers, timeout: 10)

      if response.success?
        doc = Nokogiri::HTML(response.body)

        # 스크립트와 스타일 태그 제거
        doc.css('script, style').remove

        # 본문 텍스트 추출
        body_text = doc.css('body').text
        clean_text = body_text.gsub(/\s+/, ' ').strip

        puts "추출된 텍스트 (처음 #{limit}자):"
        puts clean_text[0..limit] + (clean_text.length > limit ? "..." : "")

        # 단어 통계
        words = clean_text.split(/\s+/)
        puts "\n텍스트 통계:"
        puts "- 총 단어 수: #{words.length}개"
        puts "- 총 문자 수: #{clean_text.length}자"

        # 가장 긴 단어들
        long_words = words.select { |w| w.length > 5 }.uniq.first(5)
        puts "- 긴 단어들: #{long_words.join(', ')}" if long_words.any?

      else
        puts "텍스트 추출 실패: HTTP #{response.code}"
      end
    rescue => e
      puts "텍스트 추출 에러: #{e.message}"
    end
  end
end

# 실행 예제
crawler = SimpleNokogiriExamples.new

begin
  # 1. Ruby 사이트 크롤링
  crawler.crawl_ruby_site

  sleep(1)

  # 2. 네이버 메인 페이지 정보
  crawler.crawl_naver_trends

  sleep(1)

  # 3. HTML 구조 분석
  crawler.analyze_html_structure('https://example.com')

  sleep(1)

  # 4. 텍스트 추출
  crawler.extract_clean_text('https://www.ruby-lang.org/ko/', 300)

rescue => e
  puts "실행 중 에러: #{e.message}"
end

puts "\n=== Nokogiri 크롤링 팁 ==="
puts <<~TIPS

🔍 Nokogiri 크롤링 핵심 포인트:

1. 정적 콘텐츠에 최적화
   - HTML이 서버에서 완전히 렌더링된 페이지
   - JavaScript 없이도 내용을 볼 수 있는 사이트

2. 주요 메소드들
   - doc.at(selector): 첫 번째 요소 선택
   - doc.css(selector): 모든 매칭 요소 선택
   - element.text: 텍스트만 추출
   - element['attribute']: 속성 값 가져오기

3. 유용한 CSS 셀렉터
   - 'tag': 태그 선택
   - '.class': 클래스 선택
   - '#id': ID 선택
   - '[attr="value"]': 속성 기반 선택
   - 'parent > child': 직접 자식 선택

4. 크롤링 매너
   - 요청 간격 조절 (sleep 사용)
   - User-Agent 헤더 설정
   - 에러 처리 (try-catch)
   - robots.txt 확인

5. 한계점
   - JavaScript로 동적 로딩되는 콘텐츠는 크롤링 불가
   - 이런 경우 Playwright나 Selenium 사용 필요

TIPS

puts "=== 예제 완료! ==="
