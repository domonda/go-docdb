package docdb

import (
	"errors"
	"testing"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

func TestNewErrDocumentNotFound(t *testing.T) {
	if !errors.Is(NewErrDocumentNotFound(uu.IDv4()), errs.ErrNotFound) {
		t.Fail()
	}
	if !errs.IsErrNotFound(NewErrDocumentNotFound(uu.IDv4())) {
		t.Fail()
	}
}
