require 'nokogiri'
require 'httparty'

puts "=== Nokogiri 기본 사용법 예제 ==="

# 1. HTML 문자열 파싱
html_string = <<~HTML
  <html>
    <head>
      <title>테스트 페이지</title>
      <meta name="description" content="Nokogiri 테스트용 페이지입니다">
    </head>
    <body>
      <h1 class="title">안녕하세요!</h1>
      <div class="content">
        <p id="intro">이것은 Nokogiri 예제입니다.</p>
        <ul class="items">
          <li data-id="1">첫 번째 아이템</li>
          <li data-id="2">두 번째 아이템</li>
          <li data-id="3">세 번째 아이템</li>
        </ul>
        <a href="https://example.com" class="link">예제 링크</a>
      </div>
    </body>
  </html>
HTML

# HTML 파싱
doc = Nokogiri::HTML(html_string)

puts "\n1. 기본 요소 선택"
puts "페이지 제목: #{doc.title}"
puts "H1 텍스트: #{doc.at('h1').text}"
puts "설명 메타태그: #{doc.at('meta[name="description"]')['content']}"

puts "\n2. CSS 셀렉터 사용"
puts "클래스로 선택: #{doc.at('.title').text}"
puts "ID로 선택: #{doc.at('#intro').text}"

puts "\n3. 여러 요소 선택"
items = doc.css('li')
puts "리스트 아이템들:"
items.each_with_index do |item, index|
  puts "  #{index + 1}. #{item.text} (data-id: #{item['data-id']})"
end

puts "\n4. 속성 값 가져오기"
link = doc.at('a.link')
puts "링크 텍스트: #{link.text}"
puts "링크 URL: #{link['href']}"
puts "링크 클래스: #{link['class']}"

puts "\n5. 계층 구조 탐색"
content_div = doc.at('.content')
puts "content div의 자식 요소들:"
content_div.children.each do |child|
  next if child.text?  # 텍스트 노드 건너뛰기
  puts "  - #{child.name}: #{child.text.strip}"
end

puts "\n=== 실제 웹사이트 크롤링 예제 ==="

# 실제 웹사이트에서 데이터 가져오기
begin
  # 예제: httpbin.org에서 JSON 데이터 가져오기
  puts "\n6. 실제 웹페이지 크롤링"

  headers = {
    'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
  }

  # 간단한 HTML 페이지 테스트
  response = HTTParty.get('https://httpbin.org/html', headers: headers)

  if response.success?
    doc = Nokogiri::HTML(response.body)
    puts "크롤링 성공!"
    puts "페이지 제목: #{doc.title}"

    # h1 태그 찾기
    h1_elements = doc.css('h1')
    if h1_elements.any?
      puts "H1 태그들:"
      h1_elements.each_with_index do |h1, index|
        puts "  #{index + 1}. #{h1.text}"
      end
    end

    # 모든 링크 찾기
    links = doc.css('a[href]')
    if links.any?
      puts "링크들:"
      links.first(3).each_with_index do |link, index|
        puts "  #{index + 1}. #{link.text.strip} -> #{link['href']}"
      end
    end
  else
    puts "크롤링 실패: HTTP #{response.code}"
  end

rescue => e
  puts "에러 발생: #{e.message}"
end

puts "\n=== Nokogiri vs CSS 셀렉터 예제 ==="

# 7. 다양한 셀렉터 방법 비교
puts "\n7. 다양한 선택 방법"
doc_test = Nokogiri::HTML(html_string)

puts "- at() vs css().first:"
puts "  at('li'): #{doc_test.at('li').text}"
puts "  css('li').first: #{doc_test.css('li').first.text}"

puts "\n- 속성 기반 선택:"
puts "  [data-id='2']: #{doc_test.at('[data-id="2"]').text}"
puts "  li:nth-child(2): #{doc_test.at('li:nth-child(2)').text}"

puts "\n- 텍스트 포함 요소 찾기:"
items_with_text = doc_test.css('li').select { |li| li.text.include?('두 번째') }
puts "  '두 번째'가 포함된 요소: #{items_with_text.first.text}"

puts "\n=== Nokogiri 주요 메소드 정리 ==="
puts <<~SUMMARY

주요 메소드들:
- doc.title          # 페이지 제목
- doc.at(selector)   # 첫 번째 요소 하나만 선택
- doc.css(selector)  # 모든 매칭 요소들 선택
- element.text       # 요소의 텍스트 내용
- element['attr']    # 속성 값 가져오기
- element.children   # 자식 요소들
- element.parent     # 부모 요소

유용한 CSS 셀렉터들:
- .class            # 클래스 선택
- #id               # ID 선택
- tag               # 태그 선택
- [attr="value"]    # 속성 선택
- tag:nth-child(n)  # n번째 자식
- tag:contains("text") # 텍스트 포함 (XPath에서 사용)

SUMMARY

puts "=== 예제 완료! ==="
