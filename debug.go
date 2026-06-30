package docdb

import (
	"context"
	"fmt"
	"maps"
	"slices"

	"github.com/domonda/go-types/uu"
)

// DebugPrintDocument prints a human-readable tree of a document to the standard
// output: a document header followed by every version and the files of each
// version.
//
// The layout is indented like this (linePrefix="", indent="  "):
//
//	Document: 0c4e8f2a-...  Company: 7b1d...  Versions: 2
//	  Version: 2024-11-15_09-00-00.000  User: 3f2a...  Reason: "initial upload"
//	    File: invoice.pdf  Size: 12345  Hash: 1f8ac...
//	  Version: 2024-11-16_10-30-00.000  User: 3f2a...  Reason: "added OCR result"
//	    File: invoice.pdf  Size: 12345  Hash: 1f8ac...
//	    File: ocr.json     Size: 678    Hash: 9b3de...
//
// Every line is prefixed with linePrefix, and each deeper level of the tree
// (versions below the document, files below a version) is indented by one
// additional indent string. A VersionTime doubles as the commit time of its
// version, so it is shown as the version identifier. Files are printed sorted
// by name for deterministic output.
//
// It returns the first error encountered while reading from conn.
func DebugPrintDocument(ctx context.Context, conn Conn, docID uu.ID, linePrefix, indent string) error {
	companyID, err := conn.DocumentCompanyID(ctx, docID)
	if err != nil {
		return err
	}
	versions, err := conn.DocumentVersions(ctx, docID)
	if err != nil {
		return err
	}

	fmt.Printf("%sDocument: %s  Company: %s  Versions: %d\n", linePrefix, docID, companyID, len(versions))

	versionPrefix := linePrefix + indent
	filePrefix := versionPrefix + indent
	for _, version := range versions {
		versionInfo, err := conn.DocumentVersionInfo(ctx, docID, version)
		if err != nil {
			return err
		}
		fmt.Printf("%sVersion: %s  User: %s  Reason: %q\n", versionPrefix, version, versionInfo.CommitUserID, versionInfo.CommitReason)

		for _, filename := range slices.Sorted(maps.Keys(versionInfo.Files)) {
			file := versionInfo.Files[filename]
			fmt.Printf("%sFile: %s  Size: %d  Hash: %s\n", filePrefix, file.Name, file.Size, file.Hash)
		}
	}
	return nil
}

// DebugPrintCompanyDocuments prints a human-readable tree of all documents of a
// company to the standard output: a company header followed by every document
// (with all its versions and files) listed via conn.CompanyDocumentIDs.
//
// The layout is indented like this (linePrefix="", indent="  "):
//
//	Company: 7b1d...
//	  Document: 0c4e8f2a-...  Company: 7b1d...  Versions: 1
//	    Version: 2024-11-15_09-00-00.000  User: 3f2a...  Reason: "initial upload"
//	      File: invoice.pdf  Size: 12345  Hash: 1f8ac...
//
// Every line is prefixed with linePrefix, and each deeper level of the tree is
// indented by one additional indent string. Documents are printed sorted by
// ID. See DebugPrintDocument for the per-document layout.
//
// It returns the first error encountered while reading from conn.
func DebugPrintCompanyDocuments(ctx context.Context, conn Conn, companyID uu.ID, linePrefix, indent string) error {
	fmt.Printf("%sCompany: %s\n", linePrefix, companyID)
	docIDs, err := conn.CompanyDocumentIDs(ctx, companyID)
	if err != nil {
		return err
	}
	for _, docID := range docIDs {
		if err := DebugPrintDocument(ctx, conn, docID, linePrefix+indent, indent); err != nil {
			return err
		}
	}
	return nil
}
