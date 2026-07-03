# frozen_string_literal: true

require 'usesmileid/version'
require 'usesmileid/errors'
require 'usesmileid/generated/models'
require 'usesmileid/generated/operations'
require 'usesmileid/helpers/consent'
require 'usesmileid/helpers/user_details'
require 'usesmileid/helpers/multipart'
require 'usesmileid/client/config'
require 'usesmileid/client/transport'
require 'usesmileid/client/auth'
require 'usesmileid/client/resources'
require 'usesmileid/client/client'

# Smile ID's official server-side SDK for Ruby, covering the V3 APIs.
#
# Construct a client and call resource verbs:
#
#   require "usesmileid"
#   smile = SmileID::Client.new(partner_id: "1234", api_key: ENV.fetch("SMILE_API_KEY"))
#   accepted = smile.enhanced_kyc.verify(...)
module SmileID
end
