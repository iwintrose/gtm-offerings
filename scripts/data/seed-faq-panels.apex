// B1 — seeds the two app help panels' CMS content.
//
// Each panel is one MA_Page_Section__c (the existing 'faq' layout — the same
// one the story page's own FAQ section already renders from) plus the three
// MA_Page_Content__c rows that layout declares: eyebrow, head, items (a JSON
// list of {question, answer} pairs). Both live under the framework offering
// ('gtm'), one per app, addressed gtm::faq-bd::faq::* and
// gtm::faq-content-manager::faq::*.
//
// Run via: sf apex run --file scripts/data/seed-faq-panels.apex --target-org gtm-dev

String OFK = 'gtm';

Map<String, Object> pages = new Map<String, Object>{
    'faq-bd' => new Map<String, String>{
        'eyebrow' => 'Help',
        'head'    => 'Frequently asked questions',
        'items'   => JSON.serialize(new List<Map<String, String>>{
            new Map<String, String>{
                'question' => 'What is this page for?',
                'answer'   => 'This is the GTM Offerings home: where every offering stands, the deals in play, and how far the pages you have sent have gotten. It is the first stop for anything BD-facing.'
            },
            new Map<String, String>{
                'question' => 'How do I send a prospect page for a deal?',
                'answer'   => 'Use "New prospect page" in the header. It starts the configurator for an offering, walks you through the industry and the specifics, and gives you a link to send.'
            },
            new Map<String, String>{
                'question' => 'Where do I read an offering\'s story before a call?',
                'answer'   => 'Open the offering\'s card below and choose "Read the story". It is the same positioning a client eventually hears, read in the app rather than on the public site.'
            },
            new Map<String, String>{
                'question' => 'I found something wrong on an offering\'s story or configurator — what do I do?',
                'answer'   => 'Open "Feedback" on that offering\'s card and send a note. It goes straight to whoever writes the copy, and you will see their reply on the same card.'
            },
            new Map<String, String>{
                'question' => 'What does the funnel on the left actually count?',
                'answer'   => 'How many prospect pages you have sent, how many were opened, how many started the assessment form, and how many turned into a real request — each stage a subset of the one before it.'
            },
            new Map<String, String>{
                'question' => 'Who edits this help panel?',
                'answer'   => 'A BA, in the Content Manager app — under the Framework tile, "BD App Help (FAQ)". No deploy required.'
            }
        })
    },
    'faq-content-manager' => new Map<String, String>{
        'eyebrow' => 'Help',
        'head'    => 'Frequently asked questions',
        'items'   => JSON.serialize(new List<Map<String, String>>{
            new Map<String, String>{
                'question' => 'What is a "page" in this app?',
                'answer'   => 'One template under one offering — Story, Configurator, or Offerings Listing for an offering; Offerings Page, Industry Chooser, or an app help panel for the framework. Each page is built from sections, and each section from fields.'
            },
            new Map<String, String>{
                'question' => 'What is the difference between a draft and a publish?',
                'answer'   => 'Editing a field saves a draft automatically — nobody sees it yet. Publishing the page replaces the live values with your drafts in one move and records a version you can look back at.'
            },
            new Map<String, String>{
                'question' => 'I published something wrong. Can I get it back?',
                'answer'   => 'Every publish snapshots the value it replaced. Look at the field\'s version history to see and restore an earlier value.'
            },
            new Map<String, String>{
                'question' => 'How do I add a new section to a page?',
                'answer'   => 'Open the page, then "Add section" in the middle rail. Pick a layout — it decides which fields the new section gets. Only the layouts that page\'s renderer actually draws are offered.'
            },
            new Map<String, String>{
                'question' => 'What is the "Framework" tile for?',
                'answer'   => 'Pages that sit above any one offering: the offerings front door, the industry chooser shared by every configurator, and each app\'s own help panel — this one included.'
            },
            new Map<String, String>{
                'question' => 'Where does a new offering come from?',
                'answer'   => '"New offering" on this home page. Name it and its Story and Configurator pages are ready to build — no code or deploy involved.'
            }
        })
    }
};

List<MA_Page_Section__c> sectionsToUpsert = new List<MA_Page_Section__c>();
List<MaPageContentController.ContentRecord> contentToUpsert = new List<MaPageContentController.ContentRecord>();

for (String templateType : pages.keySet()) {
    Map<String, String> fields = (Map<String, String>) pages.get(templateType);

    sectionsToUpsert.add(new MA_Page_Section__c(
        Section_Address__c = OFK + '::' + templateType + '::faq',
        Offering_Key__c    = OFK,
        Template_Type__c   = templateType,
        Section_Key__c     = 'faq',
        Label__c           = 'FAQ',
        Layout_Type__c     = 'faq',
        Width__c           = 'standard',
        Sort_Order__c      = 10,
        Active__c          = true,
        Status__c          = 'Published'
    ));

    Integer order = 10;
    for (String fieldKey : new List<String>{ 'eyebrow', 'head', 'items' }) {
        MaPageContentController.ContentRecord r = new MaPageContentController.ContentRecord();
        r.offeringKey  = OFK;
        r.templateType = templateType;
        r.sectionKey   = 'faq';
        r.fieldKey     = fieldKey;
        r.fieldType    = fieldKey == 'items' ? 'json' : 'text';
        r.active       = true;
        r.sortOrder    = order;
        if (fieldKey == 'items') {
            r.jsonValue = fields.get(fieldKey);
        } else {
            r.textValue = fields.get(fieldKey);
        }
        contentToUpsert.add(r);
        order += 10;
    }
}

try {
    upsert sectionsToUpsert Section_Address__c;
    List<String> ids = MaPageContentController.saveContentRecords(contentToUpsert);
    Integer ok = 0;
    for (String id : ids) {
        if (String.isNotBlank(id)) ok++;
    }
    System.debug('Seed complete — ' + sectionsToUpsert.size() + ' section(s), '
        + ok + ' of ' + ids.size() + ' content row(s) upserted.');
} catch (Exception ex) {
    System.debug('Seed failed: ' + ex.getMessage());
    throw ex;
}
