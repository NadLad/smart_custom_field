# frozen_string_literal: true

module SmartCustomField
  # Admin-only formula preview.
  #
  # Evaluating a formula runs arbitrary Ruby in the context of the object, so
  # the endpoint is reserved to administrators: the same trust level as the
  # custom field form it belongs to. Nothing is ever persisted.
  class PreviewsController < ApplicationController
    before_action :require_admin

    def preview
      object = preview_object
      return render_404 if object.nil?

      render :json => Preview.for(params[:formula].to_s, object, preview_field)
    end

    private

    def preview_object
      type = params[:object_type].to_s
      return nil unless Preview.allowed_types.include?(type)

      type.constantize.find_by(:id => params[:object_id])
    end

    # A saved field carries its own format. A field being created in the admin
    # form has none yet, so the format selected in the form is used instead.
    def preview_field
      if params[:custom_field_id].present?
        CustomField.find_by(:id => params[:custom_field_id])
      elsif params[:field_format].present?
        CustomField.new(:field_format => params[:field_format].to_s)
      end
    end
  end
end
