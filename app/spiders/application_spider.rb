
class ApplicationSpider < Kimurai::Base
  @engine = :selenium_chrome
  @config = { 
    skip_request_errors: [{ error: RuntimeError, message: "404 => Net::HTTPNotFound" }],
    disable_images: true,
    # restart_if: {
    #   # Restart browser if provided memory limit (in kilobytes) is exceeded:
    #   memory_limit: 350_000
    # }
  }

  PROXIES = File.open(Rails.root.join('proxies.txt')).map {|l| l.gsub("\r\n", '') }
  # ROTATING_PROXY = 'p.webshare.io:80:http:smrijtog-rotate:plfb9in4c16j'

  def self.close_spider
    logger.info "> Stop..."
  end

  # Overwrite in_parallel function to make it not parallel(temp. fix until thread exit problem is solved)
  def in_parallel m, urls, h

    urls.each do |url|
      request_to(m, url: url, data: h[:data])
    end

  end

  # Process item data. If running in production, pass the data for processing by background workers.
  # In development, we'll simply output the data in json
  def schedule_processing data
    @product = Product.new
    @product.asin = data[:product][:asin]
    @product.description = data[:product][:description]
    @product.rating = data[:product][:rating]
    @product.star_rating = data[:product][:star_rating]
    @product.title = data[:product][:title]
    @product.save

    data[:seller].each do |seller|
      @seller = Seller.new

      check_seller = Seller.find_by merchant_id: seller[:merchant_id]
      if check_seller
        Seller.where(merchant_id: seller[:merchant_id]).first.update(
          updated_at: Time.now 
        )
      else
        @seller.merchant_id = seller[:merchant_id]
        @seller.address = seller[:address]
        @seller.city = seller[:city]
        @seller.state = seller[:state]
        @seller.country = seller[:country]
        @seller.star_rating = seller[:star_rating]
        @seller.total_rating = seller[:total_rating]
        @seller.save
      end
      
    end

    data[:product_data].each do |product_data|
      @product_data = ProductData.new
      @product_data.product_id = @product.id
      @product_data.seller_id = product_data[:seller_id]
      @product_data.price = product_data[:price]
      @product_data.ships_from = product_data[:ships_from]
      @product_data.quantity = product_data[:quantity]
      @product_data.save
    end
    save_to("app/spiders/outputs/#{self.class.to_s}_#{data[:product][:asin]}.json", data, format: :pretty_json)

  end

  # Takes HTML and converts it to text, ex. html_to_text(response.css('.container-with-lists').to_html)
  # which returns a nicely formattet text version of the p, ul, li etc tags.
  def html_to_text html
    HtmlToPlainText.plain_text(html)
  end

end
