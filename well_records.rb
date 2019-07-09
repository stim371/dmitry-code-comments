require 'open-uri'

module Importer
  module Oklahoma
    class WellRecords
      attr_reader :starts_at, :ends_at

      HOST = "http://imaging.occeweb.com/"
      OGWR_PATH = "imaging/OGWellRecords.aspx"
      AWS_BUCKET_PATH = "well_data/WY/scraped"
      RENAME = {
        "ID" => "filing_id",
        "Form" => "document_type",
        "Legal_Location" => "legal_location",
        "API" => "api",
        "Well_Name" => "well_name",
        "Operator_#" => "operator_number",
        "Eff/Test_Date" => "effective_date",
        "ScanDate" =>"scan_date"
      }.freeze

      def initialize(starts_at: , ends_at: Date.current)
        @starts_at = starts_at.to_date
        @ends_at = ends_at.to_date
      end

      def run
        goto_uri

        fill_dates
        submit_form

        collect_rows

        close_browser
      end

      private

      def collect_rows
        part_of_pages = numbers_of_pages.next

        part_of_pages.each do |page_number|
          page_link = page_link_by(page_number)

          page_link.click if page_link.exists?

          table_rows.each do |row|
            wr_params = row_params(row)

            wr_params["location_url"] = pdf_url(row)
            wr_params["effective_date"] = strpdate(wr_params["effective_date"])
            wr_params["scan_date"] = strpdate(wr_params["scan_date"])
            wr_params["document_url"] = AWS_BUCKET_PATH

            owr = OklahomaWellRecord.new(wr_params)
            owr.save

            file = download_pdf(owr.location_url)
            upload_pdf(file, owr)
          end

          return if page_number == count_of_pages

          if page_number == part_of_pages.last
            next_pages_link.click
            collect_rows
          end
        end
      end

      def strpdate(date)
        return "" unless date.present?

        Date.strptime(date, "%m/%d/%Y")
      end

      def count_of_documents
        browser.element(css: "span#lblTotalDocs").text.split(" ").first.to_i
      end

      def table_rows
        table.rows[2..-2]
      end

      def pdf_url(row)
        row.cells.first.link.href
      end

      def row_params(row)
        [
          *headers.zip(cells_text_of_row(row))
        ].to_h.transform_keys { |key| RENAME.fetch(key) }
      end

      def cells_text_of_row(row)
        row.cells.map(&:text)
      end

      def headers
        table.rows[1].text.split(" ")
      end

      def numbers_of_pages
        @numbers_of_pages ||= [*1..count_of_pages].each_slice(10).cycle
      end

      def get_numbers_of_pages
        table.rows.first.text.split(" ")
      end

      def table
        browser.table(id: "DataGrid1")
      end

      def next_pages_link
        table.rows.first.links(text: "...").last
      end

      def page_link_by(page_number)
        browser.table(id: "DataGrid1").rows.first.link(text: page_number.to_s)
      end

      def count_of_pages
        browser.element(css: "span#lblPages").text.split(" ").last.to_i
      end

      def submit_form
        browser.button(name: "Button1").click
      end

      def fill_dates
        browser.input(name: "txtScanDate").send_keys(format_date(starts_at))
        browser.input(name: "txtScanDateTo").send_keys(format_date(ends_at))
      end

      def format_date(date)
        date.strftime("%m/%d/%Y")
      end

      def uri
        URI.join(HOST, OGWR_PATH).to_s
      end

      def download_pdf(url)
        open(url)
      rescue => e
        Rails.logger.info("Download failed - #{e}")
      end

      def upload_pdf(file, owr)
        # NOTE: format "[API]+\_+[Form]+\_+[ID].pdf"
        filename = "#{owr.api}\\_#{owr.document_type}\\_#{owr.filing_id}"

        Rails.logger.info("Uploading to S3 - #{filename}.pdf")
        client.put_object(
          body: file.read,
          bucket: "bucket",
          key: "#{owr.document_url}/#{filename}.pdf",
          content_type: "application/pdf"
        )
      rescue
        Rails.logger.info("Upload failed - #{filename}.pdf")
      end

      def close_browser
        browser.close
      end

      def goto_uri
        browser.goto(uri)
      end

      def client
        @client ||= Aws::S3::Client.new
      end

      def browser
        @browser ||= Watir::Browser.new(:chrome, headless: true)
      end
    end
  end
end
