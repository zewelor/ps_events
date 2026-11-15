require "digest"
require "fileutils"
require "mini_magick"
require_relative "../event_ocr_service"
require_relative "admission"

module Ocr
  module ImagePrep
    PANEL_MARGIN_NORMALIZED = 4
    MINIATURE_MARGIN_PX = 3
    MONTHLY_SCALE_PERCENT = "150%"
    WHITE_THRESHOLD = "70%"

    module_function

    def prepare_original(source_path, output_path)
      MiniMagick.convert do |convert|
        convert << "#{source_path}[0]"
        convert.auto_orient
        convert.strip
        convert << output_path
      end

      image_record(output_path)
    rescue MiniMagick::Error, MiniMagick::Invalid => e
      raise CropError.new("Erro ao preparar imagem original: #{e.message}")
    end

    def prepare_direct(original_path, output_path, scale: EventOcrService::IMAGE_SCALE, max_size: EventOcrService::IMAGE_MAX_SIZE)
      dimensions = MiniMagick::Image.new(original_path).dimensions
      target_size = [dimensions.max * scale, max_size].min
      if target_size == dimensions.max
        FileUtils.cp(original_path, output_path)
      else
        MiniMagick.convert do |convert|
          convert << original_path
          convert.filter "Lanczos"
          convert.resize "#{target_size}x#{target_size}"
          convert.strip
          convert << output_path
        end
      end

      image_record(output_path)
    rescue MiniMagick::Error, MiniMagick::Invalid => e
      raise CropError.new("Erro ao preparar imagem direta: #{e.message}")
    end

    def pixel_box(box, width, height, panel_id: nil)
      raise GeometryError.new("Caixa delimitadora inválida", panel_id: panel_id) unless box.is_a?(Hash)

      values = %w[left top right bottom].map { |key| box[key] }
      valid = values.all? { |value| value.is_a?(Integer) && value.between?(0, 1000) } &&
        values[0] < values[2] && values[1] < values[3]
      raise GeometryError.new("Retângulo inválido: #{values.inspect}", panel_id: panel_id) unless valid

      [
        (values[0] * width / 1000.0).floor,
        (values[1] * height / 1000.0).floor,
        (values[2] * width / 1000.0).ceil,
        (values[3] * height / 1000.0).ceil
      ]
    end

    def padded_box(box, margin: PANEL_MARGIN_NORMALIZED)
      {
        "left" => [box.fetch("left") - margin, 0].max,
        "top" => [box.fetch("top") - margin, 0].max,
        "right" => [box.fetch("right") + margin, 1000].min,
        "bottom" => [box.fetch("bottom") + margin, 1000].min
      }
    end

    def crop_panel(original_path, output_path, proposed_box, width, height, panel_id:)
      pixel_box(proposed_box, width, height, panel_id: panel_id)
      left, top, right, bottom = pixel_box(padded_box(proposed_box), width, height, panel_id: panel_id)
      crop_region(original_path, output_path, left, top, right, bottom, panel_id: panel_id)
      {
        pixel_box: [left, top, right, bottom],
        crop: image_record(output_path)
      }
    end

    def map_miniatures_to_panel(miniatures, panel_pixel_box, width, height, panel_id:)
      panel_left, panel_top, panel_right, panel_bottom = panel_pixel_box
      panel_width = panel_right - panel_left
      panel_height = panel_bottom - panel_top

      miniatures.map do |box|
        x, y, r, b = pixel_box(box, width, height, panel_id: panel_id)
        unless x >= panel_left && y >= panel_top && r <= panel_right && b <= panel_bottom
          raise CropError.new("Máscara fora do painel #{panel_id}", panel_id: panel_id)
        end

        [
          [x - panel_left - MINIATURE_MARGIN_PX, 0].max,
          [y - panel_top - MINIATURE_MARGIN_PX, 0].max,
          [r - panel_left + MINIATURE_MARGIN_PX, panel_width].min,
          [b - panel_top + MINIATURE_MARGIN_PX, panel_height].min
        ]
      end
    end

    def crop_miniature(native_crop_path, output_path, box, panel_id:)
      left, top, right, bottom = box
      crop_region(native_crop_path, output_path, left, top, right, bottom, panel_id: panel_id)
      image_record(output_path)
    end

    def prepare_panel_for_reader(native_crop_path:, mask_boxes:, cleanup:, work_dir:, panel_id:, save_overlay: false, scale_percent: MONTHLY_SCALE_PERCENT)
      masked_path = File.join(work_dir, "panel-#{panel_id}-masked.png")
      MiniMagick.convert do |image|
        image << native_crop_path
        image.fill "white"
        image.stroke "white"
        image.strokewidth "1"
        mask_boxes.each { |l, t, r, b| image.draw "rectangle #{l},#{t} #{r - 1},#{b - 1}" }
        image.strip
        image << masked_path
      end

      if save_overlay
        overlay_path = File.join(work_dir, "panel-#{panel_id}-mask-overlay.png")
        MiniMagick.convert do |image|
          image << native_crop_path
          image.fill "none"
          image.stroke "red"
          image.strokewidth "2"
          mask_boxes.each { |l, t, r, b| image.draw "rectangle #{l},#{t} #{r - 1},#{b - 1}" }
          image.strip
          image << overlay_path
        end
      end

      cleaned_path = File.join(work_dir, "panel-#{panel_id}-cleaned.png")
      if cleanup == "whiten_light_background"
        gray_path = File.join(work_dir, "panel-#{panel_id}-gray.png")
        MiniMagick.convert do |image|
          image << masked_path
          image.colorspace "Gray"
          image.strip
          image << gray_path
        end
        MiniMagick.convert do |image|
          image << gray_path
          image << "-white-threshold" << WHITE_THRESHOLD
          image.strip
          image << cleaned_path
        end
      else
        FileUtils.cp(masked_path, cleaned_path)
      end

      final_path = File.join(work_dir, "panel-#{panel_id}-final-ocr.png")
      if scale_percent == "100%"
        FileUtils.cp(cleaned_path, final_path)
      else
        MiniMagick.convert do |image|
          image << cleaned_path
          image.filter "Lanczos"
          image.resize scale_percent
          image.strip
          image << final_path
        end
      end

      image_record(final_path)
    rescue MiniMagick::Error, MiniMagick::Invalid => e
      raise CropError.new("Erro ao preparar painel #{panel_id} para OCR: #{e.message}", panel_id: panel_id)
    end

    def crop_region(source_path, output_path, left, top, right, bottom, panel_id:)
      width = right - left
      height = bottom - top
      raise CropError.new("Dimensões de recorte inválidas no painel #{panel_id}", panel_id: panel_id) unless width.positive? && height.positive?

      MiniMagick.convert do |image|
        image << source_path
        image.crop "#{width}x#{height}+#{left}+#{top}"
        image.repage "+0+0"
        image.strip
        image << output_path
      end

      dimensions = MiniMagick::Image.new(output_path).dimensions
      raise CropError.new("Recorte vazio no painel #{panel_id}", panel_id: panel_id) unless dimensions.all?(&:positive?)
    rescue MiniMagick::Error, MiniMagick::Invalid => e
      raise CropError.new("Falha no recorte do painel #{panel_id}: #{e.message}", panel_id: panel_id)
    end

    def image_record(path)
      dimensions = MiniMagick::Image.new(path).dimensions
      raise CropError.new("Imagem preparada vazia: #{path}") unless File.exist?(path) && dimensions.all?(&:positive?)

      {
        path: path,
        sha256: Digest::SHA256.file(path).hexdigest,
        dimensions: dimensions,
        bytes: File.size(path)
      }
    rescue MiniMagick::Error, MiniMagick::Invalid => e
      raise CropError.new("Imagem preparada inválida (#{path}): #{e.message}")
    end
  end
end
