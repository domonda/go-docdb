package docdb

import (
	sqldriver "database/sql/driver"
	"time"

	"github.com/domonda/go-errs"
	"github.com/domonda/go-pretty"
	"github.com/domonda/go-types/nullable"
)

const (
	// VersionTimeFormat is the string format of a version time
	// returned by VersionTime.String() and parsed by VersionTimeFromString.
	VersionTimeFormat = "2006-01-02_15-04-05.000"

	sqlTimeFormat = "2006-01-02 15:04:05.999"
)

// VersionTime identifies a document version as a UTC timestamp
// truncated to millisecond precision.
// A zero value VersionTime is invalid and will be rejected by Validate.
// VersionTime implements the database/sql.Scanner and database/sql/driver.Valuer interfaces.
type VersionTime struct {
	Time time.Time
}

// NewVersionTime returns the current time as VersionTime.
func NewVersionTime() VersionTime {
	return VersionTimeFrom(time.Now())
}

// VersionTimeFrom returns a VersionTime for the given time translated to UTC and truncated to milliseconds
func VersionTimeFrom(t time.Time) VersionTime {
	if t.IsZero() {
		return VersionTime{}
	}
	return VersionTime{Time: t.UTC().Truncate(time.Millisecond)}
}

// VersionTimeFromString parses a string as VersionTime.
func VersionTimeFromString(str string) (VersionTime, error) {
	t, err := time.ParseInLocation(VersionTimeFormat, str, time.UTC)
	if err != nil {
		// Try again with SQL time format:
		t, err = time.ParseInLocation(sqlTimeFormat, str, time.UTC)
		if err != nil {
			return VersionTime{}, errs.Errorf("error parsing %q as docdb.VersionTime: %w", str, err)
		}
	}
	return VersionTime{Time: t}, nil
}

// MustVersionTimeFromString parses a string as VersionTime.
// Any error causes a panic.
func MustVersionTimeFromString(str string) VersionTime {
	version, err := VersionTimeFromString(str)
	if err != nil {
		panic(err)
	}
	return version
}

// Validate returns an error if the VersionTime is zero (invalid).
// Use Validate to check version arguments passed into functions.
func (v VersionTime) Validate() error {
	if v.Time.IsZero() {
		return errs.New("invalid zero VersionTime")
	}
	return nil
}

// String implements the fmt.Stringer interface.
func (v VersionTime) String() string {
	return v.Time.Format(VersionTimeFormat)
}

// NullableTime returns the version time as nullable.Time
func (v VersionTime) NullableTime() nullable.Time {
	return nullable.TimeFrom(v.Time)
}

var _ pretty.Stringer = VersionTime{}

// PrettyString implements the pretty.Stringer interface
// to provide a compact representation of the VersionTime
// in error messages and pretty-printed output.
func (v VersionTime) PrettyString() string {
	return v.String()
}

// MarshalText implements the encoding.TextMarshaler interface
func (v VersionTime) MarshalText() (text []byte, err error) {
	return []byte(v.String()), nil
}

// UnmarshalText implements the encoding.TextUnmarshaler interface
func (v *VersionTime) UnmarshalText(text []byte) error {
	vt, err := VersionTimeFromString(string(text))
	if err != nil {
		return err
	}
	*v = vt
	return nil
}

func (v VersionTime) After(other VersionTime) bool {
	// Truncate(time.Millisecond) on both times just to make sure it's comparable
	return v.Time.Truncate(time.Millisecond).After(other.Time.Truncate(time.Millisecond))
}

func (v VersionTime) Before(other VersionTime) bool {
	// Truncate(time.Millisecond) on both times just to make sure it's comparable
	return v.Time.Truncate(time.Millisecond).Before(other.Time.Truncate(time.Millisecond))
}

func (v VersionTime) Equal(other VersionTime) bool {
	// Truncate(time.Millisecond) on both times just to make sure it's comparable
	return v.Time.Truncate(time.Millisecond).Equal(other.Time.Truncate(time.Millisecond))
}

// Compare compares the time instant v.Time with r.Time. If v is before r, it returns -1;
// if v is after r, it returns +1; if they're the same, it returns 0.
func (v VersionTime) Compare(r VersionTime) int {
	return v.Time.Truncate(time.Millisecond).Compare(r.Time.Truncate(time.Millisecond))
}

// Scan implements the database/sql.Scanner interface.
func (v *VersionTime) Scan(value any) error {
	switch t := value.(type) {
	case time.Time:
		*v = VersionTimeFrom(t)
		return nil

	case []byte:
		vt, err := VersionTimeFromString(string(t))
		if err != nil {
			return err
		}
		*v = vt
		return nil

	case string:
		vt, err := VersionTimeFromString(t)
		if err != nil {
			return err
		}
		*v = vt
		return nil

	default:
		return errs.Errorf("unable to scan %T as docdb.VersionTime", value)
	}
}

// Value implements the driver database/sql/driver.Valuer interface.
func (v VersionTime) Value() (sqldriver.Value, error) {
	return v.Time.Truncate(time.Millisecond), v.Validate()
}
