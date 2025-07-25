<hr> 
we are not using RestoreDocument yet, so you can return a not implemented error:
https://github.com/domonda/go-docdb/blob/f1291f802814acaea1cfb7f0c3368c964f1fb761/conn.go#L72

- [x] 

<hr> 

the checkout/in stuff is already separated out to DeprecatedConn
to be able to use the simplified interface, we still need to refactor domonda-service code, see subtasks:
https://app.asana.com/1/201241326692307/project/1138407765982241/task/1138410614515456?focus=true

<hr> 

we want to use document.AddDocumentVersion ,or functions built on it, for all new doc versions:
https://github.com/domonda/domonda-service/blob/ed199e51432eb09741e2da250836acc9325eeccd/pkg/document/adddocumentversion.go#L135 (edited) 

there you pass a function that returns all changes that will be applied as atomic change as a new document version: https://github.com/domonda/domonda-service/blob/ed199e51432eb09741e2da250836acc9325eeccd/pkg/document/adddocumentversion.go#L99 (edited) 

CurrentLockID is used if the document is already locked by another operation, and you want to create the new version as part of that larger operation that manages the locking (edited) 

a generic usage example https://github.com/domonda/domonda-service/blob/ed199e51432eb09741e2da250836acc9325eeccd/pkg/docproc/rotate.go#L50 (edited) 

usage of side effects: rotating a document page doesn't need to trigger new extraction of the contents:
https://github.com/domonda/domonda-service/blob/ed199e51432eb09741e2da250836acc9325eeccd/pkg/docproc/rotate.go#L49

what needs some sort of caching or db ist the mapping between company ID and company documents, see EnumCompanyDocumentIDs

you could implement that by just looking up public.document.client_company_id . then the docdb is not completely standalone, but on the other side there are no two tables that could get out of sync

but I think it's cleaner to have a separate table in the docdb schema, that was the idea for this schema

<hr> 

methods like DocumentVersions and DocumentVersionInfo can be implemented by reading meta data json files, the info is cached in Postgres by domonda-service anyways. those methods should only be necessary for discovery of data that hasn't been restored to Postgres yet, or one time reads for larger operations that take more time anyways

so I would implement the S3Conn as simply as possible, using the same metadata files as the localfsdb and worry about caching, performance etc. when we see if it's needed (edited) 