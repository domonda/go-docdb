package localfsdb

// func (fsdb *LocalFSDB) CleanUp(ctx context.Context) (actions []docdb.ConfirmableAction, numTotalDocs int, err error) {
// 	defer errs.WrapWithFuncParams(&err)

// 	err = uuiddir.Enum(ctx, fsdb.documentsDir, func(docDir fs.File, docID [16]byte) (err error) {
// 		defer errs.WrapWithFuncParams(&err, fsdb.documentsDir)

// 		numTotalDocs++

// 		err = docDir.ListDir(func(file fs.File) error {
// 			if file.IsEmptyDir() {
// 				log.Infof("Removing empty version directory: %s", file.AbsPath()).Log()
// 				return file.Remove()
// 			}
// 			return nil
// 		})
// 		if err != nil {
// 			return err
// 		}

// 		if docDir.IsEmptyDir() {
// 			actions = append(actions, &deleteDocDir{
// 				documentsDir: fsdb.documentsDir,
// 				docDir:       docDir,
// 				because:      "it is empty",
// 			})
// 			return nil
// 		}

// 		if docDir.Join(checkOutStatusJSON).Exists() {
// 			if !fsdb.CheckedOutDocumentDir(docID).Exists() {
// 				log.Infof("Checking in document %s because there is not workspace directory anymore", docID).Log()
// 				err = fsdb.documentCheckOutStatusFile(docID).Remove()
// 				if err != nil {
// 					return err
// 				}
// 			}
// 		}

// 		doc, _, _, err := fsdb.loadDocumentTryCheckedOut(ctx, docID, systemusers.CleanUpUserID)
// 		if err != nil {
// 			actions = append(actions, &deleteDocDir{
// 				documentsDir: fsdb.documentsDir,
// 				docDir:       docDir,
// 				because:      "can't load the document",
// 			})
// 		}
// 		if doc == nil {
// 			fmt.Println("doc == nil", docID)
// 			panic("why??")
// 		}

// 		if dir := fsdb.companyDocumentDir(doc.CompanyID, doc.ID); !dir.IsDir() {
// 			log.Infof("makeCompanyDocumentDir(%s, %s): %s", doc.CompanyID, doc.ID, dir.Path()).Log()
// 			err := fsdb.makeCompanyDocumentDir(doc.CompanyID, doc.ID)
// 			if err != nil {
// 				log.ErrorCtx(ctx, "makeCompanyDocumentDir").Err(err).Log()
// 			}
// 		}
// 		return nil
// 	})

// 	if err != nil {
// 		return nil, 0, err
// 	}
// 	return actions, numTotalDocs, nil
// }

// func (fsdb *LocalFSDB) CollectStatistics(ctx context.Context) (s *docdb.Statistics, err error) {
// 	defer errs.WrapWithFuncParams(&err)

// 	var stat docdb.Statistics

// 	err = fsdb.EnumDocumentIDs(ctx, func(ctx context.Context, docID uu.ID) error {
// 		stat.NumDocuments++
// 		doc, _, err := fsdb.loadDocument(docID)
// 		if errs.IsType(err, docdb.ErrDocumentHasNoCommitedVersion{}) {
// 			return nil
// 		}
// 		if err != nil {
// 			stat.NumInvalidDocuments++
// 			log.Infof("Could not load document %s because of error %s", docID, err).Log()
// 			return nil
// 		}
// 		status, err := fsdb.documentCheckOutStatus(docID)
// 		if err != nil {
// 			log.ErrorfCtx(ctx, "Could not get document check-out status %s", docID).Err(err).Log()
// 			return err
// 		}
// 		if status != nil {
// 			stat.NumCheckedOutDocuments++
// 		}
// 		if doc.IsEmpty() {
// 			stat.NumEmptyDocuments++
// 		}
// 		versions, err := fsdb.DocumentVersions(ctx, docID)
// 		if err != nil {
// 			log.ErrorfCtx(ctx, "Could not get all document versions %s", docID).Err(err).Log()
// 			return err
// 		}
// 		stat.NumDocumentVersions += len(versions)

// 		_, versionDir, err := fsdb.latestDocumentVersionInfo(docID)
// 		if err != nil {
// 			log.ErrorfCtx(ctx, "Could not get latest document version dir %s", docID).Err(err).Log()
// 			return err
// 		}
// 		pdfInfo, err := poppler.Pdfinfo(versionDir.Join(extraction.DocPDF).LocalPath())
// 		if err != nil {
// 			log.ErrorfCtx(ctx, "Could not get %s number of pages for document %s", extraction.DocPDF, docID).Err(err).Log()
// 			return err
// 		}
// 		if pdfInfo.Pages != doc.NumPages() {
// 			stat.NumInvalidDocuments++
// 			log.Infof("Document %s %s has %d pages but %s has %d pages. Dir:\n%s", docID, extraction.DocPDF, pdfInfo.Pages, "doc.json", doc.NumPages(), versionDir.AbsPath()).Log()
// 		}

// 		docDir := fsdb.documentDir(docID)
// 		docDir.ListDirRecursive(func(file fs.File) error {
// 			stat.TotalSize += file.Size()
// 			return nil
// 		})
// 		return nil
// 	})
// 	if err != nil {
// 		return nil, err
// 	}

// 	return &stat, nil
// }

///////////////////////////////////////////////////////////////////////////////
// deleteDocDir

// type deleteDocDir struct {
// 	documentsDir fs.File
// 	docDir       fs.File
// 	because      string
// }

// func (d *deleteDocDir) Action() string {
// 	return fmt.Sprintf("Delete document directory because %s: %s", d.because, d.docDir.AbsPath())
// }

// func (d *deleteDocDir) Perform() error {
// 	log.Infof("Deleting document directory because %s: %s", d.because, d.docDir.AbsPath()).Log()
// 	return uuiddir.RemoveDir(d.documentsDir, d.docDir)
// }

// func (d *deleteDocDir) Discard() error {
// 	log.Debugf("Keeping document directory: %s", d.docDir.AbsPath()).Log()
// 	return nil
// }

// func (c *Conn) DebugGetDocumentDir(docID uu.ID) fs.File {
// 	return c.documentDir(docID)
// }

// func (c *Conn) DebugGetDocumentVersionFile(docID uu.ID, version docdb.VersionTime, filename string) (fs.File, error) {
// 	_, versionDir, err := c.documentAndVersionDir(docID, version)
// 	if err != nil {
// 		return "", err
// 	}
// 	return versionDir.Join(filename), nil
// }
