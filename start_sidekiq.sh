#!/bin/bash

echo "Starting Sidekiq for background job processing..."
echo "This will process scraping jobs and launch the browser automatically."
echo ""
echo "Press Ctrl+C to stop Sidekiq"
echo ""

bundle exec sidekiq