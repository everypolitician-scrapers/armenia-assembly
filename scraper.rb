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

def faction_from(text)
  return %w(Republican RPA) if text == '"Republican" (RPA) Faction'
  return ['Prosperous Armenia', 'PA'] if text == '"Prosperous Armenia" Faction'
  return %w(Heritage H) if text == '"Heritage" Faction'
  return ['Armenian Revolutionary Federation', 'ARF'] if text == '"Armenian Revolutionary Federation" Faction'
  return ['Rule of Law', 'ROL'] if text == '"Rule of Law" Faction'
  return %w(Independent _IND) if text == 'Not included'
  return ['Armenian National Congress', 'ANC'] if text == '"Armenian National Congress" Faction'
  raise "unknown faction: #{text}"
end

def scrape_list(url)
  noko = noko_for(url)
  noko.css('.dep_name_list a[href*="ID="]/@href').each do |href|
    link = URI.join url, href
    scrape_person(link)
  end
end

def scrape_person(url)
  noko = noko_for(url)
  box = noko.css('.dep_description')
  data = {
    id:         url.to_s[/ID=(\d+)/, 1],
    name:       noko.css('.dep_name').text.tidy,
    role:       noko.css('.dep_position').text.tidy,
    image:      noko.css('img.dep_pic/@src').text,
    district:   box.xpath('//td[div[text()="District"]]/following-sibling::td').text,
    party:      box.xpath('//td[div[text()="Party"]]/following-sibling::td').text,
    birth_date: box.xpath('//td[div[text()="Birth date"]]/following-sibling::td').text.split('.').reverse.join('-'),
    email:      box.css('a[href*="mailto:"]').text,
    term:       5,
    source:     url.to_s,
  }
  data[:image] = URI.join(url, data[:image]).to_s unless data[:image].to_s.empty?

  url_hy = URI.join url, noko.css('img.lang[title~=Armenian]').xpath('ancestor::a/@href').text
  noko_hy = noko_for(url_hy)
  data[:name__hy] = noko_hy.css('.dep_name').text.tidy

  url_ru = URI.join url, noko.css('img.lang[title~=Russian]').xpath('ancestor::a/@href').text
  noko_ru = noko_for(url_ru)
  data[:name__ru] = noko_ru.css('.dep_name').text.tidy

  factions = box.xpath('//td[div[text()="Factions"]]/following-sibling::td//table//td').reject { |n| n.text.tidy.empty? }.map do |f|
    start_date, end_date = f.css('span').text.split(' - ').map { |d| d.split('.').reverse.join('-') }
    faction, faction_id = faction_from f.css('a').text
    {
      faction_id: faction_id,
      faction:    faction,
      start_date: start_date,
      end_date:   end_date,
    }
  end
  factions.each do |f|
    ScraperWiki.save_sqlite(%i(id term start_date), data.merge(f))
  end
end

ScraperWiki.sqliteexecute('DELETE FROM data') rescue nil
scrape_list('http://parliament.am/deputies.php?lang=eng')
