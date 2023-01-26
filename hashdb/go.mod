module github.com/domonda/go-docdb/hashdb

go 1.19

// Parent module in same repo
require github.com/domonda/go-docdb v0.0.0-20230123092757-cd85b4878d9b

replace github.com/domonda/go-docdb => ../

// External
require (
	github.com/aws/aws-sdk-go-v2/config v1.17.6
	github.com/aws/aws-sdk-go-v2/service/s3 v1.30.1
	github.com/domonda/go-errs v0.0.0-20221201115330-819262069697
	github.com/domonda/go-sqldb v0.0.0-20230123092034-9bcabeb5b37e
	github.com/domonda/go-types v0.0.0-20230123091716-ceb113bdba48
	github.com/domonda/golog v0.0.0-20230124102541-81056aaba2cb
	github.com/ungerik/go-fs v0.0.0-20230126152159-caed95e133d3
)

require (
	github.com/aws/aws-sdk-go-v2 v1.17.3 // indirect
	github.com/aws/aws-sdk-go-v2/aws/protocol/eventstream v1.4.10 // indirect
	github.com/aws/aws-sdk-go-v2/credentials v1.12.19 // indirect
	github.com/aws/aws-sdk-go-v2/feature/ec2/imds v1.12.16 // indirect
	github.com/aws/aws-sdk-go-v2/internal/configsources v1.1.27 // indirect
	github.com/aws/aws-sdk-go-v2/internal/endpoints/v2 v2.4.21 // indirect
	github.com/aws/aws-sdk-go-v2/internal/ini v1.3.23 // indirect
	github.com/aws/aws-sdk-go-v2/internal/v4a v1.0.18 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/accept-encoding v1.9.11 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/checksum v1.1.22 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/presigned-url v1.9.21 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/s3shared v1.13.21 // indirect
	github.com/aws/aws-sdk-go-v2/service/sso v1.11.22 // indirect
	github.com/aws/aws-sdk-go-v2/service/ssooidc v1.13.4 // indirect
	github.com/aws/aws-sdk-go-v2/service/sts v1.16.18 // indirect
	github.com/aws/smithy-go v1.13.5 // indirect
	github.com/aymanbagabas/go-osc52 v1.2.1 // indirect
	github.com/domonda/go-encjson v0.0.0-20210830085227-1beee57a72d8 // indirect
	github.com/domonda/go-pretty v0.0.0-20220317123925-dd9e6bef129a // indirect
	github.com/fsnotify/fsnotify v1.6.0 // indirect
	github.com/lucasb-eyer/go-colorful v1.2.0 // indirect
	github.com/mattn/go-isatty v0.0.17 // indirect
	github.com/mattn/go-runewidth v0.0.14 // indirect
	github.com/muesli/termenv v0.13.0 // indirect
	github.com/rivo/uniseg v0.4.3 // indirect
	golang.org/x/exp v0.0.0-20230125214544-b3c2aaf6208d // indirect
	golang.org/x/sys v0.4.0 // indirect
)
