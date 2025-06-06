class StoresController < ApplicationController
  before_action :set_store, only: [:show, :refresh]
  
  def index
    @stores = Store.includes(:products)
    @stores = @stores.by_business_type(params[:business_type]) if params[:business_type].present?
    @stores = @stores.page(params[:page])
  end

  def show
    @products = @store.products.page(params[:page])
  end

  def create
    @store = Store.find_or_initialize_by(url: store_params[:url])
    
    if @store.save
      ScrapingJob.perform_later(@store)
      redirect_to @store, notice: '스토어 정보 수집을 시작했습니다.'
    else
      redirect_to root_path, alert: @store.errors.full_messages.join(', ')
    end
  end
  
  def scrape
    urls = params[:urls].split("\n").map(&:strip).select(&:present?)
    stores = []
    
    urls.each do |url|
      store = Store.find_or_create_by(url: url) do |s|
        s.name = url.split('/').last
        s.status = 'pending'
      end
      stores << store if store.persisted?
    end
    
    stores.each { |store| ScrapingJob.perform_later(store) }
    
    redirect_to stores_path, notice: "#{stores.count}개 스토어의 데이터 수집을 시작했습니다."
  end
  
  def refresh
    ScrapingJob.perform_later(@store)
    redirect_to @store, notice: '스토어 정보를 업데이트하고 있습니다.'
  end
  
  private
  
  def set_store
    @store = Store.find(params[:id])
  end
  
  def store_params
    params.require(:store).permit(:url, :name)
  end
end
