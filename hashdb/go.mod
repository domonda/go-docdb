module github.com/domonda/go-docdb/hashdb

go 1.22

// Parent module in same repo
require github.com/domonda/go-docdb v0.0.0-20230419114526-0c054bdc9b24

replace github.com/domonda/go-docdb => ../

// External
require (
	github.com/aws/aws-sdk-go-v2/config v1.18.32
	github.com/aws/aws-sdk-go-v2/service/s3 v1.38.1
	github.com/domonda/go-errs v0.0.0-20230810132956-1b6272f9fc8f
	github.com/domonda/go-sqldb v0.0.0-20230315204332-fb3076a77b24
	github.com/domonda/go-types v0.0.0-20230810133443-7fcb0a5a218b
	github.com/domonda/golog v0.0.0-20230810134211-c003b9d7aa25
	github.com/ungerik/go-fs v0.0.0-20230810132455-f7ff27f6fa2b
)

require (
	github.com/aws/aws-sdk-go-v2 v1.20.0 // indirect
	github.com/aws/aws-sdk-go-v2/aws/protocol/eventstream v1.4.11 // indirect
	github.com/aws/aws-sdk-go-v2/credentials v1.13.31 // indirect
	github.com/aws/aws-sdk-go-v2/feature/ec2/imds v1.13.7 // indirect
	github.com/aws/aws-sdk-go-v2/feature/s3/manager v1.11.76
	github.com/aws/aws-sdk-go-v2/internal/configsources v1.1.37 // indirect
	github.com/aws/aws-sdk-go-v2/internal/endpoints/v2 v2.4.31 // indirect
	github.com/aws/aws-sdk-go-v2/internal/ini v1.3.38 // indirect
	github.com/aws/aws-sdk-go-v2/internal/v4a v1.1.0 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/accept-encoding v1.9.12 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/checksum v1.1.32 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/presigned-url v1.9.31 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/s3shared v1.15.0 // indirect
	github.com/aws/aws-sdk-go-v2/service/sso v1.13.1 // indirect
	github.com/aws/aws-sdk-go-v2/service/ssooidc v1.15.1 // indirect
	github.com/aws/aws-sdk-go-v2/service/sts v1.21.1 // indirect
	github.com/aws/smithy-go v1.14.0 // indirect
	github.com/aymanbagabas/go-osc52/v2 v2.0.1 // indirect
	github.com/domonda/go-encjson v0.0.0-20210830085227-1beee57a72d8 // indirect
	github.com/domonda/go-pretty v0.0.0-20230810130018-8920f571470a // indirect
	github.com/fsnotify/fsnotify v1.6.0 // indirect
	github.com/jmespath/go-jmespath v0.4.0 // indirect
	github.com/lucasb-eyer/go-colorful v1.2.0 // indirect
	github.com/mattn/go-isatty v0.0.19 // indirect
	github.com/mattn/go-runewidth v0.0.15 // indirect
	github.com/muesli/termenv v0.15.2 // indirect
	github.com/rivo/uniseg v0.4.4 // indirect
	golang.org/x/sys v0.11.0 // indirect
)
