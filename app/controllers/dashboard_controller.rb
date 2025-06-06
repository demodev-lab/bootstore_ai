class DashboardController < ApplicationController
  def index
    @stores = current_user.stores.recent.limit(10)
    @search_filters = SearchFilter.active
    @total_stores = current_user.stores.count
    @total_products = Product.joins(:store).where(stores: { user_id: current_user.id }).count
  end
end
