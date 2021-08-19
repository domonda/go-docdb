package docdb

import (
	"fmt"
	"time"

	"github.com/domonda/go-types/uu"
	fs "github.com/ungerik/go-fs"
)

type CheckOutStatus struct {
	CompanyID   uu.ID
	DocID       uu.ID
	Version     VersionTime
	UserID      uu.ID
	Reason      string
	Time        time.Time
	CheckOutDir fs.File
}

func (s *CheckOutStatus) Valid() bool {
	return s != nil
}

// String implements the fmt.Stringer interface.
func (s *CheckOutStatus) String() string {
	if s == nil {
		return "CheckOutStatus<nil>"
	}
	return fmt.Sprintf("CheckOutStatus{DocID:%s, Version:%s, UserID:%s, Reason:%#v, Time:%s}", s.DocID, s.Version, s.UserID, s.Reason, s.Time)
}
