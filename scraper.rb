#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'

# require 'open-uri/cached'
# OpenURI::Cache.cache_path = '.cache'
require 'scraped_page_archive/open-uri'

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

class MembersPage < Scraped::HTML
  decorator Scraped::Response::Decorator::AbsoluteUrls

  field :member_urls do
    noko.css('.dep_name_list a[href*="ID="]/@href').map(&:text)
  end
end

class MemberPage < Scraped::HTML
  decorator Scraped::Response::Decorator::AbsoluteUrls

  field :id do
    source[/ID=(\d+)/, 1]
  end

  field :name do
    noko.css('.dep_name').text.tidy
  end

  field :role do
    noko.css('.dep_position').text.tidy
  end

  field :image do
    noko.css('img.dep_pic/@src').text
  end

  field :district do
    box.xpath('//td[div[text()="District"]]/following-sibling::td').text
  end

  field :party do
    box.xpath('//td[div[text()="Party"]]/following-sibling::td').text
  end

  field :birth_date do
    box.xpath('//td[div[text()="Birth date"]]/following-sibling::td').text.split('.').reverse.join('-')
  end

  field :email do
    box.css('a[href*="mailto:"]').text
  end

  field :term do
    5
  end

  field :source do
    url.to_s
  end

  def url_hy
    noko.css('img.lang[title~=Armenian]').xpath('ancestor::a/@href').text
  end

  def url_ru
    noko.css('img.lang[title~=Russian]').xpath('ancestor::a/@href').text
  end

  def factions
    box.xpath('//td[div[text()="Factions"]]/following-sibling::td//table//td').reject { |n| n.text.tidy.empty? }.map do |f|
      start_date, end_date = f.css('span').text.split(' - ').map { |d| d.split('.').reverse.join('-') }
      faction, faction_id = faction_from f.css('a').text
      {
        faction_id: faction_id,
        faction:    faction,
        start_date: start_date,
        end_date:   end_date,
      }
    end
  end

  private

  def box
    noko.css('.dep_description')
  end

  FACTIONS = {
    '"Republican" (RPA) Faction'                  => %w(Republican RPA),
    '"Prosperous Armenia" Faction'                => ['Prosperous Armenia', 'PA'],
    '"Heritage" Faction'                          => %w(Heritage H),
    '"Armenian Revolutionary Federation" Faction' => ['Armenian Revolutionary Federation', 'ARF'],
    '"Rule of Law" Faction'                       => ['Rule of Law', 'ROL'],
    'Not included'                                => %w(Independent _IND),
    '"Armenian National Congress" Faction'        => ['Armenian National Congress', 'ANC'],
  }.freeze

  def faction_from(text)
    FACTIONS[text] or raise "unknown faction: #{text}"
  end
end

def scrape(h)
  url, klass = h.to_a.first
  klass.new(response: Scraped::Request.new(url: url).response)
end


def scrape_list(url)
  scrape(url => MembersPage).member_urls.each { |href| scrape_person(href) }
end

def scrape_person(url)
  page = scrape(url => MemberPage)
  data = page.to_h.merge(
    name__hy: scrape(page.url_hy => MemberPage).name,
    name__ru: scrape(page.url_ru => MemberPage).name,
  )

  page.factions.each do |f|
    # puts data.merge(f)
    ScraperWiki.save_sqlite(%i(id term start_date), data.merge(f))
  end
end

ScraperWiki.sqliteexecute('DELETE FROM data') rescue nil
scrape_list('http://parliament.am/deputies.php?lang=eng')
