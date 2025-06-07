class StoresController < ApplicationController
  before_action :set_store, only: [ :show, :refresh ]

  def index
    @stores = current_user.stores.includes(:products)
    @stores = @stores.by_business_type(params[:business_type]) if params[:business_type].present?
    @stores = @stores.page(params[:page])
  end

  def show
    @products = @store.products.page(params[:page])
  end

  def create
    @store = current_user.stores.find_or_initialize_by(url: store_params[:url])
    @store.assign_attributes(store_params)

    if @store.save
      ScrapingJob.perform_later(@store)
      redirect_to @store, notice: "스토어 정보 수집을 시작했습니다."
    else
      redirect_to root_path, alert: @store.errors.full_messages.join(", ")
    end
  end

  def scrape
    urls = params[:urls].split("\n").map(&:strip).select(&:present?)
    stores = []

    urls.each do |url|
      store = current_user.stores.find_or_create_by(url: url) do |s|
        s.name = url.split("/").last
        s.status = "pending"
      end
      stores << store if store.persisted?
    end

    stores.each { |store| ScrapingJob.perform_later(store) }

    redirect_to stores_path, notice: "#{stores.count}개 스토어의 데이터 수집을 시작했습니다."
  end

  def refresh
    ScrapingJob.perform_later(@store)
    redirect_to @store, notice: "스토어 정보를 업데이트하고 있습니다."
  end

  def crawl_store
    url = params[:store_url]&.strip

    if url.blank?
      redirect_back(fallback_location: root_path, alert: "스토어 URL을 입력해주세요.")
      return
    end

    # URL 유효성 검사
    unless url.match?(/\Ahttps?:\/\/smartstore\.naver\.com\/[\w-]+/i)
      redirect_back(fallback_location: root_path, alert: "올바른 네이버 스마트스토어 URL을 입력해주세요.")
      return
    end

    begin
      # 기존 스토어가 있으면 찾고, 없으면 새로 생성
      store = current_user.stores.find_or_initialize_by(url: url)

      if store.new_record?
        store.name = url.split("/").last.humanize
        store.status = "pending"
        store.save!
      end

      # 백그라운드에서 크롤링 실행
      ScrapingJob.perform_later(store)

      redirect_to store_path(store), notice: "🚀 브라우저가 자동으로 열리고 스토어 정보를 수집합니다! 브라우저 창에서 진행 상황을 확인하실 수 있습니다."

    rescue => e
      Rails.logger.error "Store crawling error: #{e.message}"
      redirect_back(fallback_location: root_path, alert: "스토어 정보 수집 중 오류가 발생했습니다.")
    end
  end

  def search_products
    product_name = params[:product_name]&.strip

    if product_name.blank?
      redirect_back(fallback_location: root_path, alert: "상품명을 입력해주세요.")
      return
    end

    begin
      # 관련 스토어 찾기
      require_relative "../services/smartstore_product_searcher"
      relevant_stores = SmartstoreProductSearcher.find_relevant_stores(product_name)

      if relevant_stores.empty?
        redirect_back(fallback_location: root_path, alert: "관련 스토어를 찾을 수 없습니다.")
        return
      end

      # 첫 번째 관련 스토어에서 검색 수행
      store_url = relevant_stores.first

      # 스토어 생성 또는 찾기
      store = current_user.stores.find_or_initialize_by(url: store_url)

      if store.new_record?
        store.name = "#{product_name} 검색 (#{store_url.split('/').last})"
        store.description = "#{product_name} 관련 상품 검색"
        store.status = "pending"
        store.save!
      end

      # 백그라운드에서 크롤링 실행 - 검색 키워드와 함께
      ScrapingJob.perform_later(store, search_mode: true, search_query: product_name)

      redirect_to store_path(store), notice: "🔍 '#{product_name}' 관련 상품을 #{relevant_stores.size}개 스토어에서 검색합니다!"

    rescue => e
      Rails.logger.error "Product search error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_back(fallback_location: root_path, alert: "상품 검색 중 오류가 발생했습니다.")
    end
  end

  private

  def set_store
    @store = current_user.stores.find(params[:id])
  end

  def store_params
    params.require(:store).permit(:url, :name)
  end
end
