module Spree
  class SolrSearch
    def self.get_base_query(params = {})

      query = ::Sunspot.new_search(Spree::Product) do 
        with(:on_hand).greater_than 0
        with(:available_on).less_than Time.now
        with(:deleted_at).equal_to nil
        with(:price).greater_than 0
        with(:currency).equal_to Spree::Config[:currency]
        with(:is_active).equal_to true

        order_by(
              params[:order_by] ? params[:order_by] : :price,
              params[:order] ? params[:order] : :asc)

        paginate(:page => params[:page] ? params[:page].to_i : 1, 
                 :per_page => params[:per_page] ? params[:per_page].to_i : Spree::Config.products_per_page)
      end

      return query
    end

    def self.query(params)
      query = Spree::SolrSearch.get_base_query(params)

      # Facet filters start with a f_
      filters = Hash[params.reject{|k,v| not k.to_s =~ /^f_.*/}
                           .map{|k, v| [k.to_s.gsub("f_",""), v]}]

      solr_filters = {}
      filters.map{|k,v| solr_filters[k.to_sym] = Spree::SolrSearch.add_filter(query,k,v)} if not filters.empty?
      query.build {|q| q.keywords(params[:keywords]){minimum_match 1} } if params[:keywords]

      Spree::SolrFacets.filters.each_pair do |k,v| 
        Spree::SolrSearch.add_facet(query, v, solr_filters[k.to_sym], self.get_prefix(params, v))
      end

      return query
    end

    def self.add_filter(query, search_field, values)
      solr_filter = nil
      filter = Spree::SolrFacets.get_filter(search_field)

      return if not filter

      localized_field = filter[:localized] ? "#{filter[:search_field]}_#{I18n.locale}" : filter[:search_field]

      if filter[:values].try(:any?) and filter[:values].first.is_a?(Range)
        range = values.split('..').map{|d| Float(d)}
        query.build{|q| q.with(search_field, range[0]..range[1])}
      elsif filter[:multiple] 
        values = values.split("~")
        query.build do |q|
          solr_filter = q.any_of do |q|
            values.each{|v| q.with(localized_field, v)}
          end
        end
      else
        values = values.split("~")
        query.build do |q|
          solr_filter = q.all_of do |q|
            values.each{|v| q.with(localized_field, v)}
          end
        end
      end

      return solr_filter
    end

    def self.get_prefix(params, filter_options)
      search_value = params["f_#{filter_options[:search_field]}"]
      prefix = params["prefix_#{filter_options[:search_field]}"]
      return prefix if not (prefix.nil? and prefix.blank?)

      if search_value.blank? or search_value.nil?
        return filter_options[:default_prefix]
      end

      if search_value.match(/^\d*_/)
        levels = search_value.split("_")
        levels[0] = levels[0].to_i + 1

        return levels.join("_")
      else
        return ""
      end
    end

    def self.add_facet(query, filter, solr_filter, prefix)
      if filter[:values].try(:any?) and filter[:values].first.is_a?(Range)
        query.build do |q|
          q.facet(filter[:search_field]) do
            filter[:values].each do |value|
              row(value) do 
                with(filter[:search_field], value)
              end
            end
          end
        end
      else
        localized_field = filter[:localized] ? "#{filter[:search_field]}_#{I18n.locale}" : filter[:search_field]

        query.build do |q|
          if filter[:multiple]
            q.facet(localized_field, :exclude => solr_filter)
          else
            q.facet(localized_field, :prefix => prefix)
          end
        end
      end
    end

  end
end
