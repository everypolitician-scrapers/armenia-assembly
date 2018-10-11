#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

class MembersPage < Scraped::HTML
  decorator Scraped::Response::Decorator::CleanUrls

  field :member_urls do
    noko.css('.dep_name_list a[href*="ID="]/@href').map(&:text)
  end
end

class MemberPage < Scraped::HTML
  decorator Scraped::Response::Decorator::CleanUrls

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

  field :source do
    url.to_s
  end

  field :url_hy do
    noko.css('img.lang[title~=Armenian]').xpath('ancestor::a/@href').text
  end

  field :url_ru do
    noko.css('img.lang[title~=Russian]').xpath('ancestor::a/@href').text
  end

  # TODO: split this out to a fragment
  field :factions do
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
    '"Republican" (RPA) Faction'                  => %w[Republican RPA],
    '"Republican Party of Armenia" Faction'       => %w[Republican RPA],
    '"Prosperous Armenia" Faction'                => ['Prosperous Armenia', 'PA'],
    '"Heritage" Faction'                          => %w[Heritage H],
    '"Armenian Revolutionary Federation" Faction' => ['Armenian Revolutionary Federation', 'ARF'],
    '"Rule of Law" Faction'                       => ['Rule of Law', 'ROL'],
    'Not included'                                => %w[Independent _IND],
    '"Armenian National Congress" Faction'        => ['Armenian National Congress', 'ANC'],
    '"Tsarukyan" Faction'                         => %w[Tsarukyan TSAR],
    '"Way Out" Faction'                           => ['Way Out', 'WO'],
  }.freeze

  def faction_from(text)
    FACTIONS[text.tidy] or raise "unknown faction: #{text}"
  end
end

def scrape(h)
  url, klass = h.to_a.first
  klass.new(response: Scraped::Request.new(url: url).response)
end

def person_data(url)
  data = scrape(url => MemberPage).to_h
  data[:name__hy] = scrape(data.delete(:url_hy) => MemberPage).name
  data[:name__ru] = scrape(data.delete(:url_ru) => MemberPage).name
  data.delete(:factions).map { |f| data.merge(term: 6).merge(f) }
end

start = 'http://parliament.am/deputies.php?lang=eng'

# Hard-coded list of Members who were in the term, but are no longer listed
MEMBER = 'http://parliament.am/deputies.php?sel=details&ID=%s&lang=eng'
vanished_members = %w[]
vanished_urls = vanished_members.map { |id| MEMBER % id }

to_fetch = scrape(start => MembersPage).member_urls | vanished_urls
data = to_fetch.flat_map { |url| person_data(url) }
data.each { |mem| puts mem.reject { |_, v| v.to_s.empty? }.sort_by { |k, _| k }.to_h } if ENV['MORPH_DEBUG']

ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil
ScraperWiki.save_sqlite(%i[id term start_date], data)
