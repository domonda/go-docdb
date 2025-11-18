package postgres

import (
	"time"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-types/uu"
)

type Lock struct {
	ID        uu.ID     `db:"id"`
	UserID    uu.ID     `db:"user_id"`
	Reason    string    `db:"reason"`
	CreatedAt time.Time `db:"created_at"`
}

type DocumentVersionFile struct {
	DocumentVersionID uu.ID  `db:"document_version_id"`
	Name              string `db:"name"`
	Size              int64  `db:"size"`
	Hash              string `db:"hash"`

	DocumentVersion *DocumentVersion `db:"-"`
}

type DocumentVersion struct {
	ID            uu.ID              `db:"id"`
	DocumentID    uu.ID              `db:"document_id"`
	CompanyID     uu.ID              `db:"company_id"`
	Version       docdb.VersionTime  `db:"version"`
	PrevVersion   *docdb.VersionTime `db:"prev_version"`
	CommitUserID  uu.ID              `db:"commit_user_id"`
	CommitReason  string             `db:"commit_reason"`
	AddedFiles    []string           `db:"added_files"`
	RemovedFiles  []string           `db:"removed_files"`
	ModifiedFiles []string           `db:"modified_files"`
}
