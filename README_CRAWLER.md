# 🤖 BoostStoreAI Browser Automation Crawler

## How to Run the Crawler

The crawler uses Playwright to automatically open a browser and collect store data. For this to work, you need to run Sidekiq in the background.

### Step 1: Start Sidekiq (Required!)

Open a new terminal window and run:

```bash
./start_sidekiq.sh
```

Or manually:

```bash
bundle exec sidekiq
```

**Important**: Keep this terminal window open! Sidekiq processes the background jobs that launch the browser.

### Step 2: Start Rails Server

In another terminal window:

```bash
rails server
```

### Step 3: Use the Crawler

1. Go to http://localhost:3000
2. Login with your account
3. Enter a Naver Smart Store URL (e.g., https://smartstore.naver.com/saramdel)
4. Click "🚀 스토어 정보 수집 시작"

### What Happens:

1. The job is queued in Sidekiq
2. A Chrome browser window opens automatically
3. The browser navigates to the store
4. It automatically clicks on product sections
5. Scrolls to load dynamic content
6. Extracts product information
7. Saves data to the database
8. Browser closes when done

### Troubleshooting

If the browser doesn't open:

1. **Check Sidekiq is running** - Look for output in the Sidekiq terminal
2. **Check Redis is running** - Run `redis-cli ping` (should return PONG)
3. **Check logs** - Look at the Rails server output for errors

### Test Direct Scraping (Without Background Job)

To test the scraper directly:

```ruby
# In rails console
store = Store.find_or_create_by(url: "https://smartstore.naver.com/saramdel") do |s|
  s.user = User.first
  s.name = "Test Store"
end

scraper = PlaywrightStoreScraper.new(store)
scraper.scrape
```

This will open the browser immediately without using background jobs.