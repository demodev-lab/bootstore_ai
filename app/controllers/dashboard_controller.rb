class DashboardController < ApplicationController
  def index
    @stores = Store.recent.limit(10)
    @search_filters = SearchFilter.active
    @total_stores = Store.count
    @total_products = Product.count
  end
end
