module Aebus

  module EC2

    ZONES = {

        "eu-west1" =>  "eu-west-1.ec2.amazonaws.com",
        "us-east-1" =>  "ec2.us-east-1.amazonaws.com",
        "us-west-1" =>  "ec2.us-west-1.amazonaws.com",
        "ap-southeast-1" => "ec2.ap-southeast-1.amazonaws.com"
    }

    def self.zone_to_url(zone)
      ZONES[zone]
    end

  end

end