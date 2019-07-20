require "open-uri"

module NewMexico
  class CardRecords
    HOST = "https://wwwapps.emnrd.state.nm.us/"
    PERMIT_PATH = "ocd/ocdpermitting/OperatorData/PermitStatusParameters.aspx"
    AWS_BUCKET_PATH = "pdocument/well_documents/nm/permit_documents/"
    RENAME = {
      "Id" => "filing_id",
      "Type" => "document_type",
      "Description" => "document_comment",
      "Status" => "document_status",
      "Status Date" =>"scan_date"
    }.freeze

    RENAME2 = {
      "Permit:" => "permit_id",
      "Image Date:" => "scan_date",
      "Operator:" => "operator_name",
      "Current Operator:" => "operator_name",
      "Well Name & Number:" => "well_name_full",
      "Well Name and Number:" => "well_name_full",
      "Well Info:" => "well_name_full",
      "ULSTR:" => "location",
      "Previous Name:" => "previous_name",
      "New Name:" => "new_name",
      "New Operator:" => "new_name",
      "Effective Date:" => "effective_date"
    }.freeze

    def run
      browser.goto(uri)
      fill_form
      submit_form

      browser.wait_until { |b| b.table(id: "ctl00_ctl00__main_main_gvResults").exists? }

      1.upto(count_of_pages).map(&:to_s).each do |page_number|
        link = pagination.link(text: page_number)

        link.click unless link.class_name == "active"

        browser.wait_until { |b| pagination.link(text: page_number).class_name == "active" }

        rows.each do |row|
          query_params = row_params(row)
          query_params["scan_date"] = strpdate(query_params["scan_date"])
          query_params["well_card_url"] = row.link.href

          NewMexicoQueryRecord.create!(query_params)

          browser.execute_script("window.open(\"#{query_params["well_card_url"]}\")")

          card_params = table_params

          card_params["permit_id"] = card_params.fetch("permit_id", query_params.fetch("filing_id"))
          card_params["scan_date"] = card_params.fetch("scan_date", query_params.fetch("scan_date"))
          card_params["location_url"] = location_url

          if card_params["location_url"].end_with?(".pdf")
            filename =
              filename(
                file_url: card_params["location_url"],
                document_type: query_params["document_type"],
                permit_id: card_params["permit_id"],
                filing_date: filing_date(query_params["scan_date"])
              )

            card_params["document_url"] = "s3://bucket/#{AWS_BUCKET_PATH}#{filename}"

            file = download_pdf(card_params["location_url"])
            upload_pdf(file, filename)
          end

          card_params["scrape_url"] = browser.url
          card_params["well_files_url"] = well_files_url

          NewMexicoCardRecord.create!(card_params)

          browser.windows.last.close
        end
      end

      close_browser
    end

    def filing_date(date)
      date.strftime("%Y%m%d")
    end

    def filename(file_url: , document_type: , permit_id: , filing_date: )
      "#{file_url.split("/").last[0...-4]}_#{document_type}_#{permit_id}_#{filing_date}.pdf"
    end

    def pagination
      browser.element(css: "ul.pagination")
    end

    def count_of_pages
      browser.element(css: "span#ctl00_ctl00__main_main_pager_lblPageCount").text.split(" ").last.to_i
    end

    def fill_form
      current_year = Date.current.strftime("%Y")

      browser.select(name: "ctl00$ctl00$_main$main$ddlPermitType").select("All")
      browser.select(name: "ctl00$ctl00$_main$main$ddlPermitStatus").select("All")
      browser.select(name: "ctl00$ctl00$_main$main$ddlStatusYear").select(current_year)
    end

    def table_params
      browser.windows.last.use

      browser.wait_until { |b| b.fieldsets.first.exists? }

      browser.tables.first.rows.map do |row|
        row.cells.map do |c|
          c.attribute_value("textContent").squish
        end
      end.to_h.transform_keys do |key|
        RENAME2[key]
      end.select { |key, _value| key.present? }
    end

    def row_params(row)
      headers.
        zip(cells_text_of_row(row)).
        to_h.
        transform_keys { |key| RENAME[key] }
    end

    def cells_text_of_row(row)
      row.cells.map(&:text)
    end

    def location_url
      browser.fieldsets.last.links.first.href
    end

    def well_files_url
      button = browser.button(name: "ctl00$ctl00$_main$main$btnWellFile")

      button.exists? ? button.onclick.match(/'(.*)'/)[1] : ""
    end

    def headers
      browser.table.headers.map(&:text)
    end

    def rows
      browser.table.rows[1..-2]
    end

    def submit_form
      browser.button(name: "ctl00$ctl00$_main$main$btnfilter").click!
    end

    def uri
      URI.join(HOST, PERMIT_PATH).to_s
    end

    def download_pdf(url)
      open(url)
    rescue => e
      Rails.logger.info("Download failed - #{e}")
      raise
    end

    def upload_pdf(file, filename)
      Rails.logger.info("Uploading to S3 - #{filename}")
      client.put_object(
        body: file.read,
        bucket: "bucket",
        key: "#{AWS_BUCKET_PATH}#{filename}",
        content_type: "application/pdf"
      )
    rescue
      Rails.logger.info("Upload failed - #{filename}")
      raise
    end

    def close_browser
      browser.close
    end

    private

    def format_date(date)
      date.strftime("%m/%d/%Y")
    end

    def strpdate(date)
      return "" unless date.present?

      Date.strptime(date, "%m/%d/%Y")
    end

    def client
      @client ||= Aws::S3::Client.new
    end

    def browser
      @browser ||= Watir::Browser.new(:chrome, headless: true)
    end
  end
end
