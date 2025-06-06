module Api
  module V1
    class StoresController < ApplicationController
      skip_before_action :verify_authenticity_token
      
      def index
        stores = Store.includes(:products)
        stores = stores.by_business_type(params[:business_type]) if params[:business_type].present?
        
        render json: {
          stores: stores.map do |store|
            {
              id: store.id,
              name: store.name,
              url: store.url,
              product_count: store.product_count,
              average_price: store.average_price,
              business_type: store.business_type,
              status: store.status,
              scraped_at: store.scraped_at
            }
          end
        }
      end
      
      def show
        store = Store.find(params[:id])
        render json: {
          store: {
            id: store.id,
            name: store.name,
            url: store.url,
            product_count: store.product_count,
            average_price: store.average_price,
            business_type: store.business_type,
            status: store.status,
            scraped_at: store.scraped_at,
            products_count: store.products.count
          }
        }
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Store not found' }, status: :not_found
      end
    end
  end
end