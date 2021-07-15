require 'kimurai'
class AmazonScraper < ApplicationSpider

HELP = <<ENDHELP
Usage:
   scrape [-h]

   -h, --help             Show this help.
   -a, --asins           ASIN to scrape, please puts asin with correct format ex: xxxxx,yyyyy ,
   -proxy,      Use proxy, input proxy with format ip:port:type:user:pass ex: 209.127.191.180:9279:http:bkizsdyc:vp06h3iihn9d,
   -zip, --zipcode      Set zipcode of US to get delivery fee,
                            amazon,
                            ...
ENDHELP


ARGS = {
  asin: nil, 
  proxy: nil,
  zipcode: nil,
}
UNFLAGGED_ARGS = []
next_arg = UNFLAGGED_ARGS.first
ARGV.each do |arg|
  case arg
    when '-h','--help'             then ARGS[:help] = true
    when '-a','--asins'           then next_arg = :asin
    when '-zip','--zipcode'     then next_arg = :zipcode
    when '-p', '--proxy'        then next_arg = :proxy
    else
      if next_arg
        ARGS[next_arg] = arg
        UNFLAGGED_ARGS.delete( next_arg )
      end
      next_arg = UNFLAGGED_ARGS.first
  end
end

  urls = []
  $is_multiple_asin = false
  if ARGS[:asin]
    asin = ARGS[:asin].split(',') if ARGS[:asin].include? ','
    asin ||= [ARGS[:asin]]

    asin.each do |asin|
      asin = asin.strip.gsub(/\t*/, '')
      next if asin.length < 10
      urls << "https://www.amazon.com/gp/offer-listing/#{asin}"
    end

    if urls.empty?
      puts "Please input the correct ASIN!"
      exit
    end
  else
    puts "Please input the ASIN!"
    exit
  end
  urls = urls.uniq
  $is_multiple_asin = urls.length > 1

  $zip_code = 10040
  $zip_code = ARGS[:zipcode] if ARGS[:zipcode]
  $proxy = ARGS[:proxy]

  
  @engine = :selenium_chrome
  @start_urls = urls
  @config = {
    # window_size: [1280, 800],
    disable_images: false,
  }

  if(ARGS[:proxy])
    @config[:proxy] = ARGS[:proxy]
    @config[:before_request] = {
      change_proxy: true,
    }
  end
  
  def parse(response, url:, data: {})
    begin
      unless (browser.find(:css, '#glow-ingress-block').text.include? $zip_code.to_s)
        browser.find(:css, '#aod-close').click if browser.has_css?('#aod-close')
        sleep 1
        browser.find(:css, '#nav-global-location-data-modal-action').click
        sleep 2
        browser.find(:css, '#GLUXZipUpdateInput').set($zip_code)
        browser.find(:css, '#GLUXZipInputSection input[type="submit"]').click

        sleep 1
        browser.find(:css, 'span[data-action="a-popover-close"]') if browser.has_css?('span[data-action="a-popover-close"]')
        sleep 1
        browser.find(:css, '.a-popover-footer #GLUXConfirmClose').click if browser.has_css?('.a-popover-footer #GLUXConfirmClose')
        sleep 5
      end
      data = {}
      product = parse_product
      product[:asin] = url.split('/offer-listing/').last
      data[:product] = product
      data[:product_data] = []
      data[:seller] = []

      sleep 2
      browser.all(:css, '#aod-pinned-offer, #aod-offer').each do |elem|
        form_action = elem.find(:css, 'form')['action'].gsub('https://www.amazon.com', '')
        data_seller_product = parse_information(elem)
        seller = data_seller_product[:seller]
        puts "Get quantity of product"
        product_data = data_seller_product[:product]
        browser.execute_script("document.querySelector('form[action="+ '"'+form_action+'"'+"]').setAttribute('target', '_blank')")
        aod_window = browser.window_opened_by do
          browser.execute_script("document.querySelector('form[action="+ '"'+form_action+'"'+"] input[name=\"submit.addToCart\"]').click()")
        end

        browser.within_window aod_window do
          unless browser.has_css?('select[name="quantity"]')
            3.times do
              browser.refresh
              sleep 3
            end
          end
          browser.find(:css, '#hlb-view-cart-announce').click
          sleep 3
          browser.find(:css, 'select[name="quantity"]').find(:option, '10').select_option
          sleep 3
          browser.find(:css, 'input[name="quantityBox"]').set(500)
          sleep 3
          browser.find(:xpath, '//a[contains(., "Update")]/parent::span').click

          quantity_text = browser.find(:css, '.sc-inline-qty-update-msg').text rescue nil
          quantity_text ||= browser.find(:css, 'input[name="quantityBox"]').value
          quantity = quantity_text.scan(/\d+/).first
          product_data[:quantity] = quantity

          browser.find(:css, 'span[data-action="delete"] span input').click
          sleep 3
          aod_window.close
        end
        sleep 3
        data[:seller] << seller
        data[:product_data] << product_data
      end
      puts JSON.pretty_generate(data)
      schedule_processing data
    rescue => e
      browser.save_screenshot('error_screenshot.png')
      puts "Screenshot of error was saved in #{Rails.root.join('tmp','error_screenshot.png').to_s}"
      puts "Error during processing: #{$!}"
      puts "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
    sleep 500
      exit
    end
  end

  def parse_product
    puts "Get product data"
    data = {}
    page = browser.current_response
    data[:title] = browser.find(:css, 'h1#title').text rescue nil
    data[:title] ||= browser.find(:css, '.product-title-word-break').text rescue nil
    data[:title] ||= browser.find(:css, 'meta[name="keywords"]').text rescue nil
    data[:title] = browser.evaluate_script("document.getElementById('productTitle').textContent") rescue nil
    data[:title] ||= page.at_css('meta[name="keywords"]').text
    data[:description] = browser.find(:css, '#productDescription').text rescue nil
    data[:description] ||= browser.find(:xpath, '//h2[contains(., "Product description")]/following-sibling::div').text
    data[:rating] = page.at_css('#acrCustomerReviewText').text.scan(/\d*/).first
    data[:star_rating] = page.at_css('#averageCustomerReviews .a-icon-star .a-icon-alt').text.scan(/\d\.?\d?/).first.gsub('-', '.')
    data
  end

  def parse_information(elem)
    seller = {}
    product = {}
    puts "Get seller data"
    seller_url = elem.find(:css, '#aod-offer-soldBy .a-col-right a')['href'] rescue nil
    seller[:merchant_id] = seller_url.split('seller=').last.gsub(/&isAmazonFulfilled.+/i, '') if seller_url
    is_exist_seller = Seller.where(merchant_id: seller[:merchant_id]).first
    puts "Seller with id #{seller[:merchant_id]} is existed, skipped" if is_exist_seller
    product[:seller_id] = seller[:merchant_id]
    product[:ships_from] = elem.find(:css, '#aod-offer-shipsFrom .a-col-right span').text
    product[:price] = parse_price elem.find_all(:css, '.a-price >span').map { |e| e.text }.first
    seller_window = browser.window_opened_by do
      browser.execute_script( "window.open('#{seller_url}','_blank');")
      sleep 3
    end if seller_url

    if seller_url and !is_exist_seller
      browser.within_window seller_window do
        2.times do
          browser.execute_script("window.location.reload();")
          sleep 3
        end
        address_info = browser.find_all(:xpath, '//span[@class="a-text-bold" and contains(., "Business Address:")]/following-sibling::ul/li').map { |e| e.text}
        seller[:address] = address_info.join(', ')
        Geocoder.configure(lookup: :location_iq, api_key: 'pk.a89652d80b4787c83244093933692a18')
        search_address = address_info
        search_address.shift
        data_geo = Geocoder.search(search_address.join(', ')).first
        if data_geo
          seller[:city] = data_geo.data['address']['city']
          seller[:city] ||= data_geo.data['address']['town']
          seller[:state] = data_geo.data['address']['state']
          seller[:country] = data_geo.data['address']['country']
        else 
          seller[:city] = address_info[1]
          seller[:state] = address_info[2]
          seller[:country] = address_info[4]
        end
        seller[:name] = browser.find(:css, '#sellerName').text rescue nil
        seller[:name] ||= browser.find(:xpath, '//span[@class="a-text-bold" and contains(., "Business Name:")]/following-sibling::text()').text
        seller[:star_rating] = browser.find(:css, '#seller-feedback-summary .feedback-detail-stars .a-icon-alt').text.scan(/\d\.?\d?/).first
        seller[:total_rating] = browser.find(:css, '#feedback-summary-table tbody tr:last-child td:last-child').text.gsub(',', '')
        seller[:is_exist] = false
        seller_window.close
      end
    else
      seller[:is_exist] = true
    end
    return { seller: seller, product: product }
  end


  def parse_price(str)
    str.gsub('$', '').gsub(',', '.').gsub(/\n|\t|[a-z]|\+/, '').strip
  end

  def clean_string(text)
    text.gsub!(/\n|\r|\t/, "")
    text.gsub!(/\s+/, " ")
    text.gsub!(/^\s+|\s+$/, "")
    text.gsub!(/&nbsp;/, "")
    text.gsub!(/^[^0-9a-zA-Z]/, "")
    text
  end

  def process_captcha
  end

end
AmazonScraper.crawl!