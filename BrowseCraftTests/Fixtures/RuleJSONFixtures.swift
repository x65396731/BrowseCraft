// 中文注释：RuleJSONFixtures 集中保存模型完整性测试用 JSON。
// 中文注释：大块 JSON 独立出来后，模型测试文件只保留能力断言，方便 review 结构和字段覆盖。
enum RuleJSONFixtures {
    /// 中文注释：完整 V2 规则样例，同时保留旧版必填字段，用来验证新旧模型可共存。
    static let completeV2SiteRule: String = """
    {
      "version": 2,
      "name": "Complete V2 Site",
      "baseUrl": "https://example.test",
      "site": {
        "name": "Complete V2 Site",
        "domain": "example.test",
        "baseURL": "https://example.test",
        "iconURL": "https://example.test/favicon.png",
        "displayMode": "grid",
        "loginURL": "https://example.test/login",
        "language": "zh-Hans"
      },
      "urlPatterns": {
        "list": "https://example.test/list/{page}",
        "detailTemplate": {
          "template": "https://example.test/comics/{idCode:}",
          "placeholders": [
            {
              "kind": "idCode"
            }
          ]
        },
        "galleryTemplate": {
          "template": "https://example.test/chapters/{cidCode:}",
          "placeholders": [
            {
              "kind": "cidCode"
            }
          ]
        },
        "searchTemplate": {
          "template": "https://example.test/search?q={keyword:}&from={urlQuery:from}",
          "placeholders": [
            {
              "kind": "keyword",
              "encoding": "urlQueryAllowed"
            },
            {
              "kind": "urlQuery",
              "name": "from",
              "defaultValue": "home"
            }
          ]
        }
      },
      "pages": [
        {
          "id": "home",
          "title": "Home",
          "type": "home",
          "url": "https://example.test",
          "displayMode": "grid",
          "ruleRefs": {
            "list": "home-list"
          },
          "request": {
            "scope": "page",
            "mergePolicy": "mergeHeaders",
            "headers": {
              "Referer": "https://example.test/"
            }
          },
          "tabGroup": {
            "id": "home-tabs",
            "selectedTabId": "discover",
            "layout": "horizontalScroll",
            "tabs": [
              {
                "id": "discover",
                "title": "发现",
                "listRuleRef": "home-list"
              },
              {
                "id": "latest",
                "title": "更新",
                "url": "https://example.test/latest/1",
                "listRuleRef": "latest-list",
                "request": {
                  "scope": "page",
                  "headers": {
                    "X-Tab": "latest"
                  }
                },
                "context": {
                  "sectionRole": "category"
                }
              }
            ]
          },
          "sections": [
            {
              "id": "main-grid",
              "role": "main",
              "itemLayout": "verticalGrid",
              "container": {
                "selector": "section.main-grid",
                "function": "raw"
              }
            },
            {
              "id": "recommendations",
              "role": "recommendation",
              "itemLayout": "horizontalRow",
              "container": {
                "selector": "section.recommendations",
                "function": "raw"
              }
            }
          ],
          "flags": [
            "lazyImages"
          ]
        },
        {
          "id": "detail",
          "title": "Detail",
          "type": "detail",
          "url": "https://example.test/comics/{idCode:}",
          "ruleRefs": {
            "detail": "detail"
          }
        },
        {
          "id": "reader",
          "title": "Reader",
          "type": "reader",
          "displayMode": "verticalReader",
          "ruleRefs": {
            "gallery": "reader-gallery"
          }
        }
      ],
      "sharedRequest": {
        "scope": "site",
        "mergePolicy": "inherit",
        "method": "GET",
        "headers": {
          "User-Agent": "BrowseCraft"
        },
        "cookiePolicy": "browserThenCustom",
        "cookiePriority": "browser",
        "cookieScope": "site",
        "charset": "utf8",
        "needsWebView": false,
        "autoScroll": false,
        "imageRequest": {
          "mergePolicy": "mergeHeaders",
          "headers": {
            "Accept": "image/avif,image/webp,image/*"
          },
          "cookiePolicy": "browser",
          "cookiePriority": "image",
          "cookieScope": "image"
        }
      },
      "ruleSets": {
        "listRules": [
          {
            "id": "home-list",
            "url": "https://example.test/list/1",
            "item": ".card",
            "itemRule": {
              "selector": ".card",
              "selectorKind": "css",
              "function": "raw"
            },
            "fields": {
              "idCode": {
                "selector": ".card",
                "function": "attr",
                "param": "data-id"
              },
              "title": {
                "selector": ".title",
                "function": "text"
              },
              "cover": {
                "selector": "img.cover",
                "function": "attr",
                "param": "src"
              },
              "largeImage": {
                "selector": "img.large",
                "function": "attr",
                "param": "data-src"
              },
              "video": {
                "selector": "video source",
                "function": "attr",
                "param": "src"
              },
              "detailURL": {
                "selector": "a.title",
                "function": "url",
                "fallback": [
                  {
                    "selector": "a.cover",
                    "function": "url"
                  }
                ]
              },
              "uploader": {
                "selector": ".uploader",
                "function": "text"
              },
              "datetime": {
                "selector": "time",
                "function": "attr",
                "param": "datetime"
              }
            },
            "title": ".title",
            "link": "a.title@href",
            "cover": "img.cover@src",
            "type": "comic",
            "pagination": {
              "nextPage": {
                "selector": "a.next",
                "function": "url"
              },
              "pagePlaceholder": "{page:1:1}",
              "maxPages": 10,
              "stopWhenEmpty": true
            },
            "request": {
              "scope": "rule",
              "mergePolicy": "mergeHeadersAndCookies",
              "cookiePriority": "custom",
              "cookieScope": "rule"
            }
          },
          {
            "id": "latest-list",
            "url": "https://example.test/list/latest",
            "item": ".card",
            "fields": {
              "title": {
                "selector": ".title",
                "function": "text"
              },
              "detailURL": {
                "selector": "a.title",
                "function": "url"
              }
            },
            "title": ".title",
            "link": "a.title@href",
            "cover": "img.cover@src",
            "type": "comic"
          }
        ],
        "detailRules": [
          {
            "id": "detail",
            "fields": {
              "title": {
                "selector": "h1",
                "function": "text"
              },
              "cover": {
                "selector": ".cover img",
                "function": "attr",
                "param": "src"
              },
              "totalImages": {
                "selector": ".page-count",
                "function": "text",
                "functions": [
                  "text",
                  "regexReplacement"
                ],
                "regex": "(\\\\d+)",
                "replacement": "$1"
              },
              "photoAlbumLink": {
                "selector": "a.album",
                "function": "url"
              },
              "secondLevelPageURL": {
                "selector": "a.reader",
                "function": "url"
              }
            },
            "chapterRule": {
              "item": {
                "selector": ".chapter",
                "function": "raw"
              },
              "idCode": {
                "selector": ".chapter",
                "function": "attr",
                "param": "data-id"
              },
              "cidCode": {
                "selector": ".chapter",
                "function": "attr",
                "param": "data-cid"
              },
              "title": {
                "selector": ".chapter-title",
                "function": "text"
              },
              "url": {
                "selector": "a.chapter-link",
                "function": "url"
              },
              "sort": "descending"
            },
            "tagRule": {
              "item": {
                "selector": ".tags a",
                "function": "raw"
              },
              "name": {
                "selector": "this",
                "function": "text"
              },
              "url": {
                "selector": "this",
                "function": "url"
              }
            },
            "commentRule": {
              "item": {
                "selector": ".comment",
                "function": "raw"
              },
              "avatar": {
                "selector": "img.avatar",
                "function": "attr",
                "param": "src"
              },
              "username": {
                "selector": ".user",
                "function": "text"
              },
              "content": {
                "selector": ".content",
                "function": "text"
              }
            },
            "videoRule": {
              "item": {
                "selector": "video, .video",
                "function": "raw"
              },
              "url": {
                "selector": "source",
                "function": "attr",
                "param": "src"
              },
              "thumbnail": {
                "selector": "video",
                "function": "attr",
                "param": "poster"
              }
            }
          }
        ],
        "galleryRules": [
          {
            "id": "reader-gallery",
            "mainScope": {
              "selector": "main.reader",
              "function": "raw"
            },
            "item": {
              "selector": "img.page",
              "function": "raw"
            },
            "image": {
              "selector": "this",
              "function": "attr",
              "functions": [
                "attr",
                "removingPercentEncoding"
              ],
              "param": "data-src"
            },
            "thumbnail": {
              "selector": "this",
              "function": "attr",
              "param": "src"
            },
            "imageItem": "img.page",
            "imageUrl": "this@data-src",
            "pagination": {
              "nextPage": {
                "selector": "a.next",
                "function": "url"
              },
              "stopWhenEmpty": true
            },
            "request": {
              "scope": "image",
              "mergePolicy": "mergeHeaders",
              "imageRequest": {
                "headers": {
                  "Referer": "https://example.test/reader"
                },
                "cookiePriority": "image",
                "cookieScope": "image"
              }
            }
          }
        ],
        "searchRules": [
          {
            "id": "search",
            "keywordEncoding": "urlQueryAllowed",
            "url": "https://example.test/search?q={keyword:}",
            "method": "GET",
            "listRuleRef": "home-list",
            "item": {
              "selector": ".search-result",
              "function": "raw"
            },
            "fields": {
              "title": {
                "selector": ".title",
                "function": "text"
              },
              "detailURL": {
                "selector": "a.title",
                "function": "url"
              }
            }
          }
        ]
      },
      "flags": [
        "staticHTML",
        "openContent"
      ],
      "list": {
        "url": "https://example.test/list/1",
        "item": ".card",
        "title": ".title",
        "link": "a.title@href",
        "cover": "img.cover@src",
        "type": "comic"
      },
      "detail": {
        "title": "h1",
        "chapterContainer": ".chapters",
        "chapterItem": ".chapters a",
        "chapterTitle": "this",
        "chapterLink": "this@href"
      },
      "gallery": {
        "imageItem": "img.page",
        "imageUrl": "this@src"
      },
      "video": {
        "videoUrl": "https://media.example/video.mp4"
      }
    }
    """

    /// 中文注释：Runtime/Resolved Graph 测试只使用严格 V2 字段，不混入 V1 selector 字符串。
    static let strictComicV2SiteRule: String = """
    {
      "version": 2,
      "name": "Strict Comic V2 Site",
      "baseUrl": "https://example.test",
      "site": {
        "name": "Strict Comic V2 Site",
        "domain": "example.test",
        "baseURL": "https://example.test"
      },
      "pages": [
        {
          "id": "home",
          "title": "Home",
          "type": "home",
          "url": "https://example.test/list/1",
          "request": {
            "scope": "page",
            "mergePolicy": "mergeHeaders",
            "headers": { "Referer": "https://example.test/" }
          },
          "ruleRefs": { "list": "home-list" },
          "tabGroup": {
            "id": "home-tabs",
            "selectedTabId": "discover",
            "layout": "horizontalScroll",
            "tabs": [
              {
                "id": "discover",
                "title": "发现",
                "listRuleRef": "home-list"
              },
              {
                "id": "latest",
                "title": "更新",
                "url": "https://example.test/latest/1",
                "listRuleRef": "latest-list",
                "request": {
                  "scope": "page",
                  "headers": { "X-Tab": "latest" }
                },
                "context": { "sectionRole": "category" }
              }
            ]
          },
          "sections": [
            {
              "id": "main-grid",
              "role": "main",
              "itemLayout": "verticalGrid",
              "listRuleRef": "home-list",
              "container": {
                "selector": "section.main-grid",
                "selectorKind": "css",
                "function": "raw"
              }
            },
            {
              "id": "recommendations",
              "role": "recommendation",
              "itemLayout": "horizontalRow",
              "listRuleRef": "home-list",
              "container": {
                "selector": "section.recommendations",
                "selectorKind": "css",
                "function": "raw"
              }
            }
          ]
        },
        {
          "id": "detail",
          "title": "Detail",
          "type": "detail",
          "url": "https://example.test/comics/{idCode:}",
          "ruleRefs": { "detail": "detail" }
        },
        {
          "id": "reader",
          "title": "Reader",
          "type": "reader",
          "displayMode": "verticalReader",
          "ruleRefs": { "gallery": "reader-gallery" }
        },
        {
          "id": "search",
          "title": "Search",
          "type": "search",
          "url": "https://example.test/search?q={keyword:}&page={page}",
          "ruleRefs": { "search": "search" }
        }
      ],
      "sharedRequest": {
        "scope": "site",
        "mergePolicy": "inherit",
        "method": "GET",
        "headers": { "User-Agent": "BrowseCraft" },
        "needsWebView": false,
        "autoScroll": false
      },
      "ruleSets": {
        "listRules": [
          {
            "id": "home-list",
            "url": "https://example.test/list/1",
            "item": "",
            "itemRule": {
              "selector": ".card",
              "selectorKind": "css",
              "function": "raw"
            },
            "fields": {
              "idCode": {
                "selectorKind": "current",
                "function": "attr",
                "param": "data-id"
              },
              "title": {
                "selector": ".title",
                "selectorKind": "css",
                "function": "text"
              },
              "cover": {
                "selector": "img.cover",
                "selectorKind": "css",
                "function": "attr",
                "param": "src"
              },
              "detailURL": {
                "selector": "a.title",
                "selectorKind": "css",
                "function": "url",
                "param": "href"
              }
            },
            "title": "",
            "link": "",
            "type": "comic",
            "request": {
              "scope": "rule",
              "mergePolicy": "mergeHeadersAndCookies"
            }
          },
          {
            "id": "latest-list",
            "url": "https://example.test/latest/1",
            "item": "",
            "itemRule": {
              "selector": ".card",
              "selectorKind": "css",
              "function": "raw"
            },
            "fields": {
              "title": {
                "selector": ".title",
                "selectorKind": "css",
                "function": "text"
              },
              "detailURL": {
                "selector": "a.title",
                "selectorKind": "css",
                "function": "url",
                "param": "href"
              }
            },
            "title": "",
            "link": "",
            "type": "comic"
          }
        ],
        "detailRules": [
          {
            "id": "detail",
            "fields": {
              "title": {
                "selector": "h1",
                "selectorKind": "css",
                "function": "text"
              }
            },
            "chapterRule": {
              "item": {
                "selector": ".chapter",
                "selectorKind": "css",
                "function": "raw"
              },
              "title": {
                "selector": ".chapter-title",
                "selectorKind": "css",
                "function": "text"
              },
              "url": {
                "selector": "a.chapter-link",
                "selectorKind": "css",
                "function": "url",
                "param": "href"
              }
            }
          }
        ],
        "galleryRules": [
          {
            "id": "reader-gallery",
            "imageItem": "",
            "imageUrl": "",
            "item": {
              "selector": "img.page",
              "selectorKind": "css",
              "function": "raw"
            },
            "image": {
              "selectorKind": "current",
              "function": "attr",
              "param": "data-src"
            },
            "request": {
              "scope": "rule",
              "mergePolicy": "mergeHeaders",
              "imageRequest": {
                "headers": { "Referer": "https://example.test/reader" }
              }
            }
          }
        ],
        "searchRules": [
          {
            "id": "search",
            "keywordEncoding": "urlQueryAllowed",
            "url": "https://example.test/search?q={keyword:}&page={page}",
            "method": "GET",
            "item": {
              "selector": ".search-item",
              "selectorKind": "css",
              "function": "raw"
            },
            "fields": {
              "title": {
                "selector": ".title",
                "selectorKind": "css",
                "function": "text"
              },
              "detailURL": {
                "selector": "a.title",
                "selectorKind": "css",
                "function": "url",
                "param": "href"
              }
            },
            "pagination": {
              "nextPage": {
                "selector": "a.next",
                "selectorKind": "css",
                "function": "url",
                "param": "href"
              },
              "stopWhenEmpty": true
            }
          }
        ]
      },
      "list": {
        "url": "https://example.test/list/1",
        "item": ".card",
        "title": ".title",
        "link": "a.title@href",
        "type": "comic"
      }
    }
    """
}
