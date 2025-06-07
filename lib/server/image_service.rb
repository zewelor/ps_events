require "mini_magick"
require "fileutils"
require "securerandom"

class ImageService
  MAX_SIZE = 800
  QUALITY = 80
  UPLOAD_DIR = "/tmp"

  # Configure MiniMagick timeout
  MiniMagick.configure do |config|
    config.timeout = 30
  end

  def self.process_upload(uploaded_file)
    return nil unless uploaded_file && uploaded_file[:tempfile]

    # Ensure upload directory exists
    FileUtils.mkdir_p(UPLOAD_DIR)

    # Generate unique filename
    filename = "#{SecureRandom.uuid}.webp"
    output_path = File.join(UPLOAD_DIR, filename)

    begin
      # Open the uploaded image with MiniMagick
      image = MiniMagick::Image.open(uploaded_file[:tempfile].path)

      # Validate it's actually an image by checking the format
      image_format = image.type
      unless %w[JPEG PNG GIF WEBP BMP TIFF].include?(image_format)
        raise "Unsupported image format: #{image_format}"
      end      # Set format first (must be done outside combine_options)
      image.format "webp"

      # Use combine_options for better performance when doing multiple operations
      image.combine_options do |cmd|
        # Resize while maintaining aspect ratio (only if larger than MAX_SIZE)
        if image.width > MAX_SIZE || image.height > MAX_SIZE
          cmd.resize "#{MAX_SIZE}x#{MAX_SIZE}>"
        end

        # Set quality
        cmd.quality QUALITY

        # Optional: Strip metadata to reduce file size
        cmd.strip
      end

      # Write to final destination
      image.write output_path

      # Return absolute path for storage
      output_path
    rescue => e
      # Clean up the output file if it was created
      File.delete(output_path) if File.exist?(output_path)
      raise "Image processing failed: #{e.message}"
    ensure
      # Clean up temp file
      uploaded_file[:tempfile].close if uploaded_file[:tempfile] && !uploaded_file[:tempfile].closed?
    end
  end

  def self.validate_upload(uploaded_file)
    return "No file uploaded" unless uploaded_file && uploaded_file[:tempfile]

    # Check file size (limit to 10MB)
    max_size = 10 * 1024 * 1024 # 10MB in bytes
    if uploaded_file[:tempfile].size > max_size
      return "File size too large. Maximum size is 10MB."
    end

    # Check MIME type
      allowed_types = %w[
        image/jpeg image/jpg image/png image/gif
        image/webp image/bmp image/tiff image/tif
        image/heic image/heif
      ]

      unless allowed_types.include?(uploaded_file[:type])
        return "Invalid file type. Please upload an image file (JPEG, PNG, GIF, WebP, BMP, TIFF ou HEIC)."
    end

    nil # No errors
  end
end
