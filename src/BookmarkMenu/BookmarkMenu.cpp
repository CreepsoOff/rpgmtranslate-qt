#include "BookmarkMenu.hpp"

#include "BookmarkList.hpp"
#include "TabListModel.hpp"

#include <QApplication>
#include <QComboBox>
#include <QVBoxLayout>

BookmarkMenu::BookmarkMenu(QWidget* const parent) :
    QWidget(parent),
    layout_(new QVBoxLayout(this)),
    fileSelect(new QComboBox(this)),
    bookmarkList(new BookmarkList(this)) {
    setAttribute(Qt::WA_StyledBackground, true);
    setStyleSheet("BookmarkMenu { background-color: %1 }"_L1.arg(
        qApp->palette().color(QPalette::Window).name()
    ));

    fileSelect->addItem(tr("- Filter by file -"));

    connect(
        fileSelect,
        &QComboBox::currentIndexChanged,
        this,
        [this](const u32 index) -> void {
        if (index == 0) {
            for (const u32 row : range<u32>(0, bookmarkList->rowCount())) {
                bookmarkList->setRowHidden(row, false);
            }
        } else {
            const QString filename = fileSelect->currentText();

            for (const u32 row : range<u32>(0, bookmarkList->rowCount())) {
                const Bookmark& bookmark = bookmarkList->bookmark(row);
                bookmarkList->setRowHidden(
                    row,
                    QL1SV(bookmark.filename.data()) != filename
                );
            }
        }

        bookmarkList->refilter();
    }
    );

    connect(
        bookmarkList,
        &BookmarkList::bookmarkClicked,
        this,
        [this](const QL1SV file, const u32 row) -> void {
        emit bookmarkClicked(file, row);
    }
    );

    layout_->addWidget(fileSelect);
    layout_->addWidget(bookmarkList);
    adjustSize();
    hide();
}

void BookmarkMenu::addBookmark(
    const QStringView description,
    const QStringView file,
    const u32 row
) {
    shiftIndices(file, row, true);
    bookmarkList->appendRow(description, file, row);
}

void BookmarkMenu::updateBookmark(const u32 targetRow, const QString& text) {
    for (const u32 row : range<u32>(0, bookmarkList->rowCount())) {
        Bookmark& bookmark = bookmarkList->bookmark(row);

        if (bookmark.row == targetRow) {
            bookmark.description = text;
        }
    }
};

void BookmarkMenu::removeBookmark(const u32 targetRow) {
    for (const u32 row : range<u32>(0, bookmarkList->rowCount())) {
        Bookmark& bookmark = bookmarkList->bookmark(row);

        if (bookmark.row == targetRow) {
            bookmarkList->removeRow(row);
        }
    }
}

void BookmarkMenu::shiftIndices(
    const QStringView file,
    const u32 row,
    const bool rowAdded
) {
    if (rowAdded) {
        for (const u32 idx : range<u32>(0, bookmarkList->rowCount())) {
            Bookmark& bookmark = bookmarkList->bookmark(idx);

            if (QL1SV(bookmark.filename.data()) == file &&
                bookmark.row >= row) {
                bookmark.row += 1;
            }
        }
    } else {
        for (const u32 idx : range<u32>(0, bookmarkList->rowCount())) {
            Bookmark& bookmark = bookmarkList->bookmark(idx);

            if (QL1SV(bookmark.filename.data()) == file && bookmark.row > row) {
                bookmark.row -= 1;
            }
        }
    }
};

void BookmarkMenu::clear() {
    bookmarkList->clear();
    fileSelect->clear();
    fileSelect->addItem(tr("- Filter by file -"));
}

void BookmarkMenu::setFiles(const vector<TabListItem>& files) {
    for (const auto& file : files) {
        fileSelect->addItem(file.name);
    }
}