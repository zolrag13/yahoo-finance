require 'nokogiri'
require 'open-uri'
# YahooFinance Module for YahooFinance gem
module YahooFinance
  # FinanceUtils Module
  module FinanceUtils
    def self.included(base)
      base.extend(self)
    end

    MARKETS = OpenStruct.new(
      us: OpenStruct.new(
        nasdaq: OpenStruct.new(
          url: "http://www.nasdaq.com/screening/companies-by-name.aspx?letter=0&exchange=nasdaq&render=download"),
        nyse: OpenStruct.new(
          url: "http://www.nasdaq.com/screening/companies-by-name.aspx?letter=0&exchange=nyse&render=download"),
        amex: OpenStruct.new(
          url: "http://www.nasdaq.com/screening/companies-by-name.aspx?letter=0&exchange=amex&render=download")))

    MARKET_NAMES = %w[nyse nasdaq amex]

    Company = Struct.new(:symbol, :name, :last_sale, :market_cap, :ipo_year, :sector, :industry, :summary_quote, :market)
    Sector = Struct.new(:name)
    Industry = Struct.new(:sector, :name)

    def map_company(row, market)
      Company.new(row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[7], market)
    end

    def companies(country, markets = MARKET_NAMES)
      return [] unless MARKETS[country]
      markets = Array(markets)
      if markets.any?
        markets.map { |market| companies_by_market(country)[market] }.flatten
      else
        companies_by_market(country).values.flatten
      end
    end

    def companies_by_market(country, markets = MARKET_NAMES)
      Array(markets).inject({}) do |h, market|
        companies = []
        next unless MARKETS[country][market]
        CSV.foreach(open(MARKETS[country][market].url)) do |row|
          next if row.first == "Symbol"
          companies << map_company(row, market)
        end
        h[market] = companies
        h
      end
    end

    def sectors(country, markets = MARKET_NAMES)
      companies(country, markets).map { |c| Sector.new(c.sector) }.uniq
    end

    def industries(country, markets = MARKET_NAMES)
      companies(country, markets).map { |c| Industry.new(c.sector, c.industry) }.uniq
    end

    SYMBOL_CHANGE_URL = "http://www.nasdaq.com/markets/stocks/symbol-change-history.aspx"

    SORT_BY = [
      'EFFECTIVE',
      'NEWSYMBOL',
      'OLDSYMBOL'
    ]

    ORDER = {
      'desc' => 'Y',
      'asc' => 'N'
    }

    def build_url(base_url, params)
      "#{base_url}?#{params.map{|k, v| "#{k}=#{v}"}.join("&")}"
    end

    def symbol_changes(sort_by='EFFECTIVE', order='desc')
      return unless SORT_BY.include?(sort_by)
      return unless ORDER.has_key?(order)
      params = {
        sortby: sort_by,
        descending: ORDER[order]
      }
      (1..20).to_a.map do |page|
        params[:page] = page
        get_symbol_changes(build_url(SYMBOL_CHANGE_URL, params))
      end.flatten
    end

    def get_symbol_changes(url)
      doc = Nokogiri::HTML(open(url))
      table = doc.css("#SymbolChangeList_table")
      rows = table.css('tr')
      return [] if rows.empty?

      cols = rows[0].css('th').to_a
      effective_date_col = cols.index { |c| c.text.strip == 'Effective Date' }
      old_col = cols.index { |c| c.text.strip == 'Old Symbol' }
      new_col = cols.index { |c| c.text.strip == 'New Symbol' }

      rows.drop(0).inject([]) do |data, row|
        divs = row.css('td')
        if !divs.empty? && divs[0].text.strip != 'No records found.'
          data << OpenStruct.new({
            effective_date: Date.strptime(divs[effective_date_col].text, '%m/%d/%Y').to_s,
            old_symbol: divs[old_col].text.strip,
            new_symbol: divs[new_col].text.strip
          })
        end
        data
      end
    end

    def symbols_by_market(country, market)
      symbols = []
      market = MARKETS.send(country).send(market)
      return symbols if market.nil?
      CSV.foreach(open(market.url)) do |row|
        next if row.first == "Symbol"
        symbols.push(row.first.gsub(" ", ""))
      end
      symbols
    end
  end
end
