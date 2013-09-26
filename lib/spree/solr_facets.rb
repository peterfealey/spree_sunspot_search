module Spree
  class SolrFacets
    @@filters = {}

    cattr_accessor :filters, :instance_accessor => false

    def self.add(filter)
      @@filters[filter[:search_field].to_sym] = filter
    end

    def self.get_filter(name)
      @@filters[name.to_sym]
    end

  end
end