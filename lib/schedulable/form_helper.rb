module Schedulable
  module FormHelper

    STYLES = {
      default: {
        field_html: {class: 'field'},
        input_wrapper: {tag: 'div'}
      },
      bootstrap: {
        field_html: {class: ''},
        num_field_html: {class: 'form-control'},
        date_select_html: {class: 'form-control'},
        date_select_wrapper: {tag: 'div', class: 'form-inline'},
        datetime_select_html: {class: 'form-control'},
        datetime_select_wrapper: {tag: 'div', class: 'form-inline'},
        collection_select_html: {class: 'form-control'},
        collection_check_boxes_item_wrapper: {tag: 'div', class: 'btn-group-toggle'}
      }
    }

    def self.included(base)
      ActionView::Helpers::FormBuilder.instance_eval do
        include FormBuilderMethods
      end
    end

    module FormBuilderMethods

      def schedule_select(attribute, input_options = {})

        template = @template

        available_periods = input_options[:available_periods] || ['singular', 'daily', 'weekly', 'monthly']

        # I18n
        weekdays = Date::DAYNAMES.map(&:downcase)
        weekdays = weekdays.slice(1..7) << weekdays.slice(0)

        # day_names = I18n.t('date.day_names', default: "")
        # day_names = day_names.blank? ? weekdays.map { |day| day.capitalize } : day_names.slice(1..7) << day_names.slice(0)
        # day_labels = Hash[weekdays.zip(day_names)]
        day_labels = Hash[weekdays.zip(['Mon','Tue','Wed','Thu','Fri','Sat','Sun'])]

        # Pass in default month names when missing in translations
        month_names = I18n.t('date.month_names', default: "")
        month_names = month_names.blank? ? Date::MONTHNAMES : month_names

        # Pass in default order when missing in translations
        date_order = I18n.t('date.order', default: [:year, :month, :day])
        date_order = date_order.map { |order|
          order.to_sym
        }

        # Setup date_options
        date_options = {
          order: date_order,
          use_month_names: month_names
        }

        datetime_options = { minute_step: 5 }

        # Get config options
        config_options = Schedulable.config.form_helper.present? ? Schedulable.config.form_helper : {style: :default}

        # Merge input options
        input_options = config_options.merge(input_options)

        # Setup input types
        input_types = {date: :date_select, start_time: :time_select, end_time: :time_select, datetime: :datetime_select}.merge(input_options[:input_types] || {})

        # Setup style option
        if input_options[:style].is_a?(Symbol) || input_options[:style].is_a?(String)
          style_options = STYLES.has_key?(input_options[:style]) ? STYLES[input_options[:style]] : STYLES[:default]
        elsif input_options[:style].is_a?(Hash)
          style_options = input_options[:style]
        else
          style_options = STYLES[:default]
        end

        # Merge with input options
        style_options = style_options.merge(input_options)

        # Init style properties
        style_options[:field_html]||= {}

        style_options[:label_html]||= {}
        style_options[:label_wrapper]||= {}

        style_options[:input_html]||= {}
        style_options[:input_wrapper]||= {}

        style_options[:number_field_html]||= {}
        style_options[:number_field_wrapper]||= {}

        style_options[:date_select_html]||= {}
        style_options[:date_select_wrapper]||= {}

        style_options[:time_select_html]||= {}
        style_options[:time_select_wrapper]||= {}

        style_options[:collection_select_html]||= {}
        style_options[:collection_select_wrapper]||= {}

        style_options[:collection_check_boxes_item_html]||= {}
        style_options[:collection_check_boxes_item_wrapper]||= {}

        # Merge with default input selector
        style_options[:number_field_html] = style_options[:input_html].merge(style_options[:number_field_html])
        style_options[:number_field_wrapper] = style_options[:input_wrapper].merge(style_options[:number_field_wrapper])

        style_options[:date_select_html] = style_options[:input_html].merge(style_options[:date_select_html])
        style_options[:date_select_wrapper] = style_options[:input_wrapper].merge(style_options[:date_select_wrapper])

        style_options[:collection_select_html] = style_options[:input_html].merge(style_options[:collection_select_html])
        style_options[:collection_select_wrapper] = style_options[:input_wrapper].merge(style_options[:collection_select_wrapper])

        style_options[:collection_check_boxes_item_html] = style_options[:input_html].merge(style_options[:collection_check_boxes_item_html])
        style_options[:collection_check_boxes_item_wrapper] = style_options[:input_wrapper].merge(style_options[:collection_check_boxes_item_wrapper])

        # Here comes the logic...

        # Javascript element id
        field_id = @object_name.to_s.gsub(/\]\[|[^-a-zA-Z0-9:.]/,"_").sub(/_$/,"") + "_" + attribute.to_s

        @template.content_tag("div", {id: field_id, class: 'col-12'}) do
          @template.content_tag("div", {class: 'form-row'}) do
            self.fields_for(attribute, @object.send(attribute.to_s) || @object.send("build_" + attribute.to_s)) do |f|

            # Rule Select
            @template.content_tag("div", style_options[:field_html].merge(class: 'col-12 mb-1') ) do
              select_output = f.collection_select(:rule, available_periods, lambda { |v| return v}, lambda { |v| I18n.t("schedulable.rules.#{v}", default: v.capitalize) }, {include_blank: false}, style_options[:collection_select_html])
              content_wrap(@template, select_output, style_options[:collection_select_wrapper])
            end <<

            # Weekly Checkboxes
            @template.content_tag("div", style_options[:field_html].merge({class: 'col-12 mb-2 mt-2', data: {group: 'weekly'}})) do
              content_wrap(@template, f.label(:day), style_options[:label_wrapper]) <<
              @template.content_tag("div", class: 'row row-days') do

                f.collection_check_boxes(:day, weekdays, lambda { |v| return v}, lambda { |v| (day_labels[v]).html_safe}) do |cb|
                  check_box_output = cb.check_box(style_options[:collection_check_boxes_item_html])
                  text = cb.text
                  nested_output = cb.label({class: 'btn btn-lg btn-outline-success', style: 'width: 100%'}) do |l|
                    check_box_output + text
                  end

                  wrap = content_wrap(@template, nested_output, style_options[:collection_check_boxes_item_wrapper])
                  content_wrap(@template, wrap, tag: 'div', class: 'col')
                end
              end
            end <<

            # Monthly Checkboxes
            @template.content_tag("div", style_options[:field_html].merge({data: {group: 'monthly'}})) do
              f.fields_for :day_of_week, OpenStruct.new(f.object.day_of_week || {}) do |db|
                content_wrap(@template, f.label(:day_of_week), style_options[:label_wrapper]) <<
                @template.content_tag("div", nil, style: 'min-width: 280px; display: table') do
                  @template.content_tag("div", nil, style: 'display: table-row') do
                    @template.content_tag("span", nil, style: 'display: table-cell;') <<
                    ['1st', '2nd', '3rd', '4th', 'last'].reduce(''.html_safe) { | content, item |
                      content << @template.content_tag("span", I18n.t("schedulable.monthly_week_names.#{item}", default: item.to_s), style: 'display: table-cell; text-align: center')
                    }
                  end <<
                  weekdays.reduce(''.html_safe) do | content, weekday |
                    content << @template.content_tag("div", nil, style: 'display: table-row') do
                      @template.content_tag("span", day_labels[weekday] || weekday, style: 'display: table-cell') <<
                      db.collection_check_boxes(weekday.to_sym, [1, 2, 3, 4, -1], lambda { |i| i} , lambda { |i| "&nbsp;".html_safe}, checked: db.object.send(weekday)) do |cb|
                        @template.content_tag("span", style: 'display: table-cell; text-align: center') { cb.check_box() }
                      end
                    end
                  end
                end
              end
            end <<

            # StartTime Select
            @template.content_tag("div", class: 'form-group col-md-6', data: {group: 'singular,daily,weekly,monthly'}) do
              content_wrap(@template, f.label('Start date', style_options[:label_html]), style_options[:label_wrapper]) <<
              @template.content_tag("div", class: 'input-group') do
                content_wrap(@template, f.text_field(:start_time_date, class: 'form-control datepicker')) <<
                @template.content_tag("div", class: 'input-group-append') do
                  '<button type="button" class="btn btn-primary"><i class="icon-calendar"></i></button>'.html_safe
                end
              end
            end <<

            @template.content_tag("div", class: 'form-group col-md-6', data: {group: 'singular,daily,weekly,monthly'}) do
              content_wrap(@template, f.label('Time', style_options[:label_html]), style_options[:label_wrapper]) <<
              @template.content_tag("div", class: 'input-group') do
                content_wrap(@template, f.text_field(:start_time_time, class: 'form-control')) <<
                @template.content_tag("div", class: 'input-group-append') do
                  '<button type="button" class="btn btn-primary"><i class="icon-clock"></i></button>'.html_safe
                end
              end
            end <<

            # EndTime Select
            @template.content_tag("div", class: 'form-group col-md-6', data: {group: 'singular,daily,weekly,monthly'}) do
              content_wrap(@template, f.label('End date', style_options[:label_html]), style_options[:label_wrapper]) <<
              @template.content_tag("div", class: 'input-group') do
                content_wrap(@template, f.text_field(:end_time_date, class: 'form-control datepicker')) <<
                @template.content_tag("div", class: 'input-group-append') do
                  '<button type="button" class="btn btn-primary"><i class="icon-calendar"></i></button>'.html_safe
                end
              end
            end <<

            @template.content_tag("div", class: 'form-group col-md-6', data: {group: 'singular,daily,weekly,monthly'}) do
              content_wrap(@template, f.label('Time', style_options[:label_html]), style_options[:label_wrapper]) <<
              @template.content_tag("div", class: 'input-group') do
                content_wrap(@template, f.text_field(:end_time_time, class: 'form-control')) <<
                @template.content_tag("div", class: 'input-group-append') do
                  '<button type="button" class="btn btn-primary"><i class="icon-clock"></i></button>'.html_safe
                end
              end
            end <<

            # Optional Fields...

            # Interval Number Field
            (if input_options[:interval]
              @template.content_tag("div", style_options[:field_html].merge({data: {group: 'daily,weekly,monthly'}})) do
                content_wrap(@template, f.label(:interval, style_options[:label_html]), style_options[:label_wrapper]) <<
                content_wrap(@template, f.number_field(:interval, style_options[:number_field_html]), style_options[:number_field_wrapper])
              end
            else
              f.hidden_field(:interval, value: 1)
            end) <<

             # Until Date Time Select
            (if input_options[:until]
              # Effective date Select
              @template.content_tag("div", class: 'form-group col-md-6', data: {group: 'singular,daily,weekly,monthly'}) do
                content_wrap(@template, f.label('Repeat until date', style_options[:label_html]), style_options[:label_wrapper]) <<
                @template.content_tag("div", class: 'input-group') do
                  content_wrap(@template, f.text_field(:until_date, class: 'form-control datepicker')) <<
                  @template.content_tag("div", class: 'input-group-append') do
                    '<button type="button" class="btn btn-primary"><i class="icon-calendar"></i></button>'.html_safe
                  end
                end
              end <<

              @template.content_tag("div", class: 'form-group col-md-6', data: {group: 'singular,daily,weekly,monthly'}) do
                content_wrap(@template, f.label('Time', style_options[:label_html]), style_options[:label_wrapper]) <<
                @template.content_tag("div", class: 'input-group') do
                  content_wrap(@template, f.text_field(:until_time, class: 'form-control')) <<
                  @template.content_tag("div", class: 'input-group-append') do
                    '<button type="button" class="btn btn-primary"><i class="icon-clock"></i></button>'.html_safe
                  end
                end
              end


            else
              f.hidden_field(:until, value: nil)
            end) <<

            # Count Number Field
            if input_options[:count]
              @template.content_tag("div", style_options[:field_html].merge({data: {group: 'daily,weekly,monthly'}})) do
                content_wrap(@template, f.label(:count, style_options[:label_html]), style_options[:label_wrapper]) <<
                content_wrap(@template, f.number_field(:count, style_options[:number_field_html]), style_options[:number_field_wrapper])
              end
            else
               f.hidden_field(:count, value: 0)
            end <<

            # Effective date Select
            @template.content_tag("div", class: 'form-group col-md-6', data: {group: 'singular,daily,weekly,monthly'}) do
              content_wrap(@template, f.label('Effective date', style_options[:label_html]), style_options[:label_wrapper]) <<
              @template.content_tag("div", class: 'input-group') do
                content_wrap(@template, f.text_field(:effective_time_date, class: 'form-control datepicker')) <<
                @template.content_tag("div", class: 'input-group-append') do
                  '<button type="button" class="btn btn-primary"><i class="icon-calendar"></i></button>'.html_safe
                end
              end
            end <<

            @template.content_tag("div", class: 'form-group col-md-6', data: {group: 'singular,daily,weekly,monthly'}) do
              content_wrap(@template, f.label('Time', style_options[:label_html]), style_options[:label_wrapper]) <<
              @template.content_tag("div", class: 'input-group') do
                content_wrap(@template, f.text_field(:effective_time_time, class: 'form-control')) <<
                @template.content_tag("div", class: 'input-group-append') do
                  '<button type="button" class="btn btn-primary"><i class="icon-clock"></i></button>'.html_safe
                end
              end
            end

          end

          end
        end <<

        # Javascript
        template.javascript_tag(
          "(function() {" <<
          "  var container = document.querySelectorAll('##{field_id}'); container = container[container.length - 1]; " <<
          "  var select = container.querySelector(\"select[name*='rule']\"); " <<
          "  function update() {" <<
          "    var value = this.value;" <<
          "    [].slice.call(container.querySelectorAll(\"*[data-group]\")).forEach(function(elem) { " <<
          "      var groups = elem.getAttribute('data-group').split(',');" <<
          "      if (groups.indexOf(value) >= 0) {" <<
          "        elem.style.display = ''" <<
          "      } else {" <<
          "        elem.style.display = 'none'" <<
          "      }" <<
          "    });" <<
          "  }" <<
          "  if (typeof jQuery !== 'undefined') { jQuery(select).on('change', update); } else { select.addEventListener('change', update); }" <<
          "  update.call(select);" <<
          "  document.querySelectorAll('.row-days input[checked]').forEach(function(element){" <<
          "    element.closest('label.btn').classList.add('active');" <<
          "  });" <<
          "  function toggleActiveClass(event){ event.target.closest('label.btn').classList.toggle('active');} " <<
          "  document.querySelectorAll('input[type=checkbox]').forEach(function(element){" <<
          "    element.addEventListener('change', toggleActiveClass  )" <<
          "  });" <<
          "})()"
        )

      end

      private
        def content_wrap(template, content, options = nil)
          if options.present? && options.has_key?(:tag)
            template.content_tag(options[:tag], content, options.except(:tag))
          else
            content
          end
        end
    end
  end
end
