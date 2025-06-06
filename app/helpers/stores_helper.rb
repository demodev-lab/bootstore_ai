module StoresHelper
  def store_status_class(status)
    case status
    when 'pending'
      'bg-gray-600 text-gray-200'
    when 'scraping'
      'bg-blue-600 text-blue-200'
    when 'completed'
      'bg-green-600 text-green-200'
    when 'failed'
      'bg-red-600 text-red-200'
    else
      'bg-gray-600 text-gray-200'
    end
  end
end
