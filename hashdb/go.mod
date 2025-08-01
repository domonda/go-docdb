module github.com/domonda/go-docdb/hashdb

go 1.25

replace github.com/domonda/go-docdb => ..

require github.com/domonda/go-docdb v0.0.0-00010101000000-000000000000 // replaced

require (
	github.com/aws/aws-sdk-go-v2/config v1.29.18
	github.com/aws/aws-sdk-go-v2/service/s3 v1.84.1
	github.com/domonda/go-errs v0.0.0-20250603150208-71d6de0c48ea
	github.com/domonda/go-sqldb v0.0.0-20250526131900-d60a57e937c5
	github.com/domonda/go-types v0.0.0-20250711130302-a138ad20cd49
	github.com/domonda/golog v0.0.0-20250620142312-a23446a321e4
	github.com/ungerik/go-fs v0.0.0-20250610091738-d3e54d2e9850
)

require (
	github.com/aws/aws-sdk-go-v2 v1.36.6 // indirect
	github.com/aws/aws-sdk-go-v2/aws/protocol/eventstream v1.6.11 // indirect
	github.com/aws/aws-sdk-go-v2/credentials v1.17.71 // indirect
	github.com/aws/aws-sdk-go-v2/feature/ec2/imds v1.16.33 // indirect
	github.com/aws/aws-sdk-go-v2/feature/s3/manager v1.17.76
	github.com/aws/aws-sdk-go-v2/internal/configsources v1.3.37 // indirect
	github.com/aws/aws-sdk-go-v2/internal/endpoints/v2 v2.6.37 // indirect
	github.com/aws/aws-sdk-go-v2/internal/ini v1.8.3 // indirect
	github.com/aws/aws-sdk-go-v2/internal/v4a v1.3.37 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/accept-encoding v1.12.4 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/checksum v1.7.5 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/presigned-url v1.12.18 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/s3shared v1.18.18 // indirect
	github.com/aws/aws-sdk-go-v2/service/sso v1.25.6 // indirect
	github.com/aws/aws-sdk-go-v2/service/ssooidc v1.30.4 // indirect
	github.com/aws/aws-sdk-go-v2/service/sts v1.34.1 // indirect
	github.com/aws/smithy-go v1.22.4 // indirect
	github.com/aymanbagabas/go-osc52/v2 v2.0.1 // indirect
	github.com/bahlo/generic-list-go v0.2.0 // indirect
	github.com/buger/jsonparser v1.1.1 // indirect
	github.com/domonda/go-encjson v0.0.0-20250402115751-77a50fd88c01 // indirect
	github.com/domonda/go-pretty v0.0.0-20250602142956-1b467adc6387 // indirect
	github.com/fsnotify/fsnotify v1.9.0 // indirect
	github.com/invopop/jsonschema v0.13.0 // indirect
	github.com/lib/pq v1.10.9 // indirect
	github.com/lucasb-eyer/go-colorful v1.2.0 // indirect
	github.com/mailru/easyjson v0.9.1 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	github.com/muesli/termenv v0.16.0 // indirect
	github.com/rivo/uniseg v0.4.7 // indirect
	github.com/wk8/go-ordered-map/v2 v2.1.8 // indirect
	golang.org/x/sys v0.37.0 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)
