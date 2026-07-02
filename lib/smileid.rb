# frozen_string_literal: true

require 'smileid/version'
require 'smileid/errors'
require 'smileid/generated/models'
require 'smileid/generated/operations'
require 'smileid/helpers/consent'
require 'smileid/helpers/user_details'
require 'smileid/helpers/multipart'
require 'smileid/client/config'
require 'smileid/client/transport'
require 'smileid/client/auth'
require 'smileid/client/resources'
require 'smileid/client/client'

# Smile ID's official server-side SDK for Ruby, covering the V3 APIs.
#
# Construct a client and call resource verbs:
#
#   require "smileid"
#   smile = SmileID::Client.new(partner_id: "1234", api_key: ENV.fetch("SMILE_API_KEY"))
#   accepted = smile.enhanced_kyc.verify(...)
module SmileID
end
