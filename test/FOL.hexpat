struct Header {
    u16 formDefinitionIndex; // The index number of the form definition
    u16 lastUsedBlock; // the last block used in the file. It is known not to be accurate in FirstChoice files
    u16 totalFileBlocks; // number of blocks in the file, minus the header
    u16 dataRecords; // the number of data records held in the file
    u8 magicString[14]; // the magic string
    u16 availableDBFields; // the number of fields in the schema
    u16 formLength; // number of blocks the schema takes up
    u16 formRevisions; // number of schema revisions. 1 indexed
    u16 _1; // padding
    u16 emptiesLength; // number of empties blocks
    u16 tableViewIndex; // index of the table view, if any
    u16 programRecordIndex; // index of the program record, if any
    u16 _2; // padding
    u16 _3; // padding
    u8 nextFieldSize; // size of the next field
    u8 diskVar[128-41];  // @DISKVAR value for formulas};
};

enum  BlockType : u16 {
    Empty = 0x0,
    DataContinuation = 0x01,
    FormDescriptionContinuation = 0x02,
    TableViewContinuation = 0x03,
    FormulaContinuation = 0x04,
    DataRecord = 0x81,
    FormDescriptionView = 0x82,
    TableView = 0x83,
    Formula = 0x84,
};

struct TextField {
    be u16 len;
    u8  chars[len];
};
struct Block {
    BlockType type;
    match(type){
        (BlockType::FormDescriptionView):{
        u16 num_form_blocks;
        be u16 len_lines_on_screen;
        be u16 len_lines;
        u8 data [120];
        }
        (_): {
            u8 data[126];
        }
    }
};

struct Empty : Block{};
struct FormDescriptionView : Block{
    BlockType type;
    TextField data[];
    
};

struct FOLFile{
    Header header;
    Block blocks[header.totalFileBlocks];
};


FOLFile file @0x0;