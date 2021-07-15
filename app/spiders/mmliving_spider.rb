require 'kimurai'
require 'uri'
require 'net/http'

class MmlivingSpider < ApplicationSpider
  @engine = :selenium_chrome
  @start_urls = ["https://www.mmliving.dk/leje/"]
  @config = {
    retry_request_errors: [{ error: Net::HTTPFatalError }, { error: Net::ReadTimeout }, { error: OpenSSL::SSL::SSLError, skip_on_failure: true }]
  }

  def parse(response, url:, data: {})
    data = response.css('.caselist .case-container').map do |elem|
      {
        url: absolute_url(elem.at_css('a')[:href], base: 'https://www.mmliving.dk'),
        property_type: elem.css('.case-description .case-fact:contains("Type") .case-fact-value')&.text&.downcase,
        rent: elem.css('.case-description .case-fact:contains("Leje pr. md.:") .case-fact-value')&.text,
        square_meters: elem.at_css('.case-description .case-fact:contains("Boligareal") .case-fact-value')&.text&.to_i,
        room_count: elem.at_css('.case-description .case-fact:contains("Værelser") .case-fact-value')&.text&.to_i,
        headline: elem.at_css('.case-headline')&.text,
        subheadline: elem.at_css('.case-subheadline')&.text
      }
    end

    # in_parallel :parse_listing, data.pluck(:url), data: data, threads: 1
  end


  def parse_listing response, url:, data: {}
    begin
      item = { external_source: self.class.to_s, external_link: url }
      data_item = data.find {|d| d[:url] == url }

      item[:external_id] = response.css('.facts .caseNumber .value').text
      item[:title] = response.css('.module-content h1.title').text
      item[:description] =  html_to_text(response.css('.description p').to_html)

      item[:property_type] = parse_property_type data_item[:property_type]

      item[:rent] = parse_price data_item[:rent]
      item[:square_meters] = data_item[:square_meters]
      item[:room_count] = data_item[:room_count]
      item[:room_count] ||= item[:description][/\d+(\s+|\-)(\s*|\w+)værelse/].split(/\s|\-/).first.to_i
  
      item[:zipcode] = data_item[:subheadline].split(' ').first rescue nil
      item[:city] = data_item[:subheadline].split(' ').second rescue nil

      sub_address = data_item[:headline].split(',').first
      item[:address] = [sub_address, item[:zipcode], item[:city]].join(', ')

      item[:deposit] = parse_price response.css('.economics .priceRentDeposit .value').text
      item[:prepaid_rent] = parse_price response.css('.economics .priceRentUpfront .value').text

      waterandheating = response.css('.economics .priceAccountHeatingWater .value').text
      item[:water_cost] = parse_price waterandheating.split('/').first
      item[:heating_cost] = parse_price waterandheating.split('/').last

      item[:floor_plan_images] = response.css('#case-plan .slick-list img').map{|img| img['src']}.uniq
      item[:images] = response.css('#case-image .slide img').map{|img| img['data-lazy']}.uniq

      item[:elevator] = response.css('.hasElevator')&.text&.downcase&.include?('elevatorja')
      item[:balcony] = response.css('.hasBalcony')&.text&.downcase.include?('altanja')

      item[:latitude] = response.at_css('#case-map .googlemap')["data-cord-x"] rescue nil
      item[:longitude] = response.at_css('#case-map .googlemap')["data-cord-y"] rescue nil
     
      item[:landlord_name] = 'MMLiving'
      item[:landlord_email] = 'info@mmliving.dk'
      item[:landlord_phone] = '+4582307300'

      schedule_processing(item)
    rescue => e

      logger.error e.message
      logger.error data_item
      raise e if Rails.env.development?
    end
  end

  private

  def parse_price str
    return nil if str.nil?
    str.gsub(/[^\d]/, '').to_f
  end

  def parse_property_type type_str
    return :apartment if type_str.downcase == 'ejerlejlighed'
    return :house if type_str.downcase.include? 'villa'
    nil
  end

end
MmlivingSpider.crawl!