package docdb

import (
	"context"

	"github.com/domonda/go-types/uu"
)

// newDummyDocumentConn returns a MockConn serving a single dummy document
// with two versions and a fixed company, user, and files, for use in the
// DebugPrint examples.
func newDummyDocumentConn(docID, companyID, userID uu.ID) *MockConn {
	v1 := MustVersionTimeFromString("2024-11-15_09-00-00.000")
	v2 := MustVersionTimeFromString("2024-11-16_10-30-00.000")

	invoice := FileInfo{Name: "invoice.pdf", Size: 12345, Hash: "1f8ac0d3"}
	ocr := FileInfo{Name: "ocr.json", Size: 678, Hash: "9b3de1a7"}

	versionInfos := map[VersionTime]*VersionInfo{
		v1: {
			CompanyID:    companyID,
			DocID:        docID,
			Version:      v1,
			CommitUserID: userID,
			CommitReason: "initial upload",
			Files:        map[string]FileInfo{invoice.Name: invoice},
		},
		v2: {
			CompanyID:    companyID,
			DocID:        docID,
			Version:      v2,
			PrevVersion:  &v1,
			CommitUserID: userID,
			CommitReason: "added OCR result",
			Files:        map[string]FileInfo{invoice.Name: invoice, ocr.Name: ocr},
		},
	}

	return &MockConn{
		CompanyDocumentIDsMock: func(ctx context.Context, _ uu.ID) (uu.IDSlice, error) {
			return uu.IDSlice{docID}, nil
		},
		DocumentCompanyIDMock: func(ctx context.Context, _ uu.ID) (uu.ID, error) {
			return companyID, nil
		},
		DocumentVersionsMock: func(ctx context.Context, _ uu.ID) ([]VersionTime, error) {
			return []VersionTime{v1, v2}, nil
		},
		DocumentVersionInfoMock: func(ctx context.Context, _ uu.ID, version VersionTime) (*VersionInfo, error) {
			return versionInfos[version], nil
		},
	}
}

func ExampleDebugPrintDocument() {
	docID := uu.IDFrom("0c4e8f2a-0000-0000-0000-000000000000")
	companyID := uu.IDFrom("7b1d3c00-0000-0000-0000-000000000000")
	userID := uu.IDFrom("3f2a1100-0000-0000-0000-000000000000")

	conn := newDummyDocumentConn(docID, companyID, userID)

	_ = DebugPrintDocument(context.Background(), conn, docID, "", "  ")

	// Output:
	// Document: 0c4e8f2a-0000-0000-0000-000000000000  Company: 7b1d3c00-0000-0000-0000-000000000000  Versions: 2
	//   Version: 2024-11-15_09-00-00.000  User: 3f2a1100-0000-0000-0000-000000000000  Reason: "initial upload"
	//     File: invoice.pdf  Size: 12345  Hash: 1f8ac0d3
	//   Version: 2024-11-16_10-30-00.000  User: 3f2a1100-0000-0000-0000-000000000000  Reason: "added OCR result"
	//     File: invoice.pdf  Size: 12345  Hash: 1f8ac0d3
	//     File: ocr.json  Size: 678  Hash: 9b3de1a7
}

func ExampleDebugPrintCompanyDocuments() {
	docID := uu.IDFrom("0c4e8f2a-0000-0000-0000-000000000000")
	companyID := uu.IDFrom("7b1d3c00-0000-0000-0000-000000000000")
	userID := uu.IDFrom("3f2a1100-0000-0000-0000-000000000000")

	conn := newDummyDocumentConn(docID, companyID, userID)

	_ = DebugPrintCompanyDocuments(context.Background(), conn, companyID, "", "  ")

	// Output:
	// Company: 7b1d3c00-0000-0000-0000-000000000000
	//   Document: 0c4e8f2a-0000-0000-0000-000000000000  Company: 7b1d3c00-0000-0000-0000-000000000000  Versions: 2
	//     Version: 2024-11-15_09-00-00.000  User: 3f2a1100-0000-0000-0000-000000000000  Reason: "initial upload"
	//       File: invoice.pdf  Size: 12345  Hash: 1f8ac0d3
	//     Version: 2024-11-16_10-30-00.000  User: 3f2a1100-0000-0000-0000-000000000000  Reason: "added OCR result"
	//       File: invoice.pdf  Size: 12345  Hash: 1f8ac0d3
	//       File: ocr.json  Size: 678  Hash: 9b3de1a7
}
