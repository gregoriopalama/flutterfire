// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cloud_firestore_platform_interface/src/method_channel/method_channel_firestore.dart';
import 'package:cloud_firestore_platform_interface/src/method_channel/method_channel_transaction.dart';
import 'package:cloud_firestore_platform_interface/src/method_channel/method_channel_field_value.dart';
import 'package:cloud_firestore_platform_interface/src/method_channel/utils/firestore_message_codec.dart';

import 'test_common.dart';
import 'test_firestore_message_codec.dart';

void main() {
  initializeMethodChannel();

  group('MethodChannelFirestore()', () {
    int mockHandleId = 0;
    FirebaseApp app;
    MethodChannelFirestore firestore;
    final List<MethodCall> log = <MethodCall>[];
    CollectionReferencePlatform collectionReference;
    QueryPlatform collectionGroupQuery;
    TransactionPlatform transaction;
    const Map<String, dynamic> kMockDocumentSnapshotData = <String, dynamic>{
      '1': 2
    };
    const Map<String, dynamic> kMockSnapshotMetadata = <String, dynamic>{
      "hasPendingWrites": false,
      "isFromCache": false,
    };
    const MethodChannel firebaseCoreChannel =
        MethodChannel('plugins.flutter.io/firebase_core');

    setUp(() async {
      mockHandleId = 0;
      // Required for FirebaseApp.configure
      firebaseCoreChannel.setMockMethodCallHandler(
        (MethodCall methodCall) async {},
      );
      app = await FirebaseApp.configure(
        name: 'testApp',
        options: const FirebaseOptions(
          googleAppID: '1:1234567890:ios:42424242424242',
          gcmSenderID: '1234567890',
        ),
      );
      firestore = MethodChannelFirestore(app: app);
      collectionReference = firestore.collection('foo');
      collectionGroupQuery = firestore.collectionGroup('bar');
      transaction = MethodChannelTransaction(0, firestore.app.name);
      MethodChannelFirestore.channel
          .setMockMethodCallHandler((MethodCall methodCall) async {
        log.add(methodCall);
        switch (methodCall.method) {
          case 'Query#addSnapshotListener':
            final int handle = mockHandleId++;
            // Wait before sending a message back.
            // Otherwise the first request didn't have the time to finish.
            // ignore: unawaited_futures
            Future<void>.delayed(Duration.zero).then<void>((_) {
              // TODO(hterkelsen): Remove this when defaultBinaryMessages is in stable.
              // https://github.com/flutter/flutter/issues/33446
              // ignore: deprecated_member_use
              BinaryMessages.handlePlatformMessage(
                MethodChannelFirestore.channel.name,
                MethodChannelFirestore.channel.codec.encodeMethodCall(
                  MethodCall('QuerySnapshot', <String, dynamic>{
                    'app': app.name,
                    'handle': handle,
                    'paths': <String>["${methodCall.arguments['path']}/0"],
                    'documents': <dynamic>[kMockDocumentSnapshotData],
                    'metadatas': <Map<String, dynamic>>[kMockSnapshotMetadata],
                    'metadata': kMockSnapshotMetadata,
                    'documentChanges': <dynamic>[
                      <String, dynamic>{
                        'oldIndex': -1,
                        'newIndex': 0,
                        'type': 'DocumentChangeType.added',
                        'document': kMockDocumentSnapshotData,
                        'metadata': kMockSnapshotMetadata,
                      },
                    ],
                  }),
                ),
                (_) {},
              );
            });
            return handle;
          case 'DocumentReference#addSnapshotListener':
            final int handle = mockHandleId++;
            // Wait before sending a message back.
            // Otherwise the first request didn't have the time to finish.
            // ignore: unawaited_futures
            Future<void>.delayed(Duration.zero).then<void>((_) {
              // TODO(hterkelsen): Remove this when defaultBinaryMessages is in stable.
              // https://github.com/flutter/flutter/issues/33446
              // ignore: deprecated_member_use
              BinaryMessages.handlePlatformMessage(
                MethodChannelFirestore.channel.name,
                MethodChannelFirestore.channel.codec.encodeMethodCall(
                  MethodCall('DocumentSnapshot', <String, dynamic>{
                    'handle': handle,
                    'path': methodCall.arguments['path'],
                    'data': kMockDocumentSnapshotData,
                    'metadata': kMockSnapshotMetadata,
                  }),
                ),
                (_) {},
              );
            });
            return handle;
          case 'Query#getDocuments':
            return <String, dynamic>{
              'paths': <String>["${methodCall.arguments['path']}/0"],
              'documents': <dynamic>[kMockDocumentSnapshotData],
              'metadatas': <Map<String, dynamic>>[kMockSnapshotMetadata],
              'metadata': kMockSnapshotMetadata,
              'documentChanges': <dynamic>[
                <String, dynamic>{
                  'oldIndex': -1,
                  'newIndex': 0,
                  'type': 'DocumentChangeType.added',
                  'document': kMockDocumentSnapshotData,
                  'metadata': kMockSnapshotMetadata,
                },
              ],
            };
          case 'DocumentReference#setData':
            return true;
          case 'DocumentReference#get':
            if (methodCall.arguments['path'] == 'foo/bar') {
              return <String, dynamic>{
                'path': 'foo/bar',
                'data': <String, dynamic>{'key1': 'val1'},
                'metadata': kMockSnapshotMetadata,
              };
            } else if (methodCall.arguments['path'] == 'foo/notExists') {
              return <String, dynamic>{
                'path': 'foo/notExists',
                'data': null,
                'metadata': kMockSnapshotMetadata,
              };
            }
            throw PlatformException(code: 'UNKNOWN_PATH');
          case 'Firestore#runTransaction':
            return <String, dynamic>{'1': 3};
          case 'Transaction#get':
            if (methodCall.arguments['path'] == 'foo/bar') {
              return <String, dynamic>{
                'path': 'foo/bar',
                'data': <String, dynamic>{'key1': 'val1'},
                'metadata': kMockSnapshotMetadata,
              };
            } else if (methodCall.arguments['path'] == 'foo/notExists') {
              return <String, dynamic>{
                'path': 'foo/notExists',
                'data': null,
                'metadata': kMockSnapshotMetadata,
              };
            }
            throw PlatformException(code: 'UNKNOWN_PATH');
          case 'Transaction#set':
            return null;
          case 'Transaction#update':
            return null;
          case 'Transaction#delete':
            return null;
          case 'WriteBatch#create':
            return 1;
          default:
            return null;
        }
      });
      log.clear();
    });

    test('multiple apps', () async {
      expect(FirestorePlatform.instance, equals(MethodChannelFirestore()));
      final FirebaseApp app = FirebaseApp(name: firestore.app.name);
      expect(firestore, equals(MethodChannelFirestore(app: app)));
    });

    test('settings', () async {
      final FirebaseApp app = FirebaseApp(name: "testApp2");
      final MethodChannelFirestore firestoreWithSettings =
          MethodChannelFirestore(app: app);
      await firestoreWithSettings.settings(
        persistenceEnabled: true,
        host: null,
        sslEnabled: true,
        cacheSizeBytes: 500000,
      );
      expect(log, <Matcher>[
        isMethodCall('Firestore#settings', arguments: <String, dynamic>{
          'app': firestoreWithSettings.app.name,
          'persistenceEnabled': true,
          'host': null,
          'sslEnabled': true,
          'cacheSizeBytes': 500000,
        }),
      ]);
    });

    group('Transaction', () {
      test('runTransaction', () async {
        final Map<String, dynamic> result = await firestore.runTransaction(
            (TransactionPlatform tx) async {},
            timeout: const Duration(seconds: 3));

        expect(log, <Matcher>[
          isMethodCall('Firestore#runTransaction', arguments: <String, dynamic>{
            'app': app.name,
            'transactionId': 0,
            'transactionTimeout': 3000
          }),
        ]);
        expect(result, equals(<String, dynamic>{'1': 3}));
      });

      test('get', () async {
        final DocumentReferencePlatform documentReference =
            firestore.document('foo/bar');
        final DocumentSnapshotPlatform snapshot =
            await transaction.get(documentReference);
        expect(snapshot.reference.firestore, firestore);
        expect(log, <Matcher>[
          isMethodCall('Transaction#get', arguments: <String, dynamic>{
            'app': app.name,
            'transactionId': 0,
            'path': documentReference.path
          })
        ]);
      });

      test('get notExists', () async {
        final DocumentReferencePlatform documentReference =
            firestore.document('foo/notExists');
        await transaction.get(documentReference);
        expect(log, <Matcher>[
          isMethodCall('Transaction#get', arguments: <String, dynamic>{
            'app': app.name,
            'transactionId': 0,
            'path': documentReference.path
          })
        ]);
      });

      test('delete', () async {
        final DocumentReferencePlatform documentReference =
            firestore.document('foo/bar');
        await transaction.delete(documentReference);
        expect(log, <Matcher>[
          isMethodCall('Transaction#delete', arguments: <String, dynamic>{
            'app': app.name,
            'transactionId': 0,
            'path': documentReference.path
          })
        ]);
      });

      test('update', () async {
        final DocumentReferencePlatform documentReference =
            firestore.document('foo/bar');
        final DocumentSnapshotPlatform documentSnapshot =
            await documentReference.get();
        final Map<String, dynamic> data = documentSnapshot.data;
        data['key2'] = 'val2';
        await transaction.set(documentReference, data);
        expect(log, <Matcher>[
          isMethodCall('DocumentReference#get', arguments: <String, dynamic>{
            'app': app.name,
            'path': 'foo/bar',
            'source': 'default',
          }),
          isMethodCall('Transaction#set', arguments: <String, dynamic>{
            'app': app.name,
            'transactionId': 0,
            'path': documentReference.path,
            'data': <String, dynamic>{'key1': 'val1', 'key2': 'val2'}
          })
        ]);
      });

      test('set', () async {
        final DocumentReferencePlatform documentReference =
            firestore.document('foo/bar');
        final DocumentSnapshotPlatform documentSnapshot =
            await documentReference.get();
        final Map<String, dynamic> data = documentSnapshot.data;
        data['key2'] = 'val2';
        await transaction.set(documentReference, data);
        expect(log, <Matcher>[
          isMethodCall('DocumentReference#get', arguments: <String, dynamic>{
            'app': app.name,
            'path': 'foo/bar',
            'source': 'default',
          }),
          isMethodCall('Transaction#set', arguments: <String, dynamic>{
            'app': app.name,
            'transactionId': 0,
            'path': documentReference.path,
            'data': <String, dynamic>{'key1': 'val1', 'key2': 'val2'}
          })
        ]);
      });
    });

    group('Blob', () {
      test('hashCode equality', () async {
        final Uint8List bytesA = Uint8List(8);
        bytesA.setAll(0, <int>[0, 2, 4, 6, 8, 10, 12, 14]);
        final Blob a = Blob(bytesA);
        final Uint8List bytesB = Uint8List(8);
        bytesB.setAll(0, <int>[0, 2, 4, 6, 8, 10, 12, 14]);
        final Blob b = Blob(bytesB);
        expect(a.hashCode == b.hashCode, isTrue);
      });
      test('hashCode not equal', () async {
        final Uint8List bytesA = Uint8List(8);
        bytesA.setAll(0, <int>[0, 2, 4, 6, 8, 10, 12, 14]);
        final Blob a = Blob(bytesA);
        final Uint8List bytesB = Uint8List(8);
        bytesB.setAll(0, <int>[1, 2, 4, 6, 8, 10, 12, 14]);
        final Blob b = Blob(bytesB);
        expect(a.hashCode == b.hashCode, isFalse);
      });
    });

    group('CollectionsReference', () {
      test('id', () async {
        expect(collectionReference.id, equals('foo'));
      });
      test('parent', () async {
        final DocumentReferencePlatform docRef =
            collectionReference.document('bar');
        expect(docRef.parent().id, equals('foo'));
        expect(collectionReference.parent(), isNull);
      });
      test('path', () async {
        expect(collectionReference.path, equals('foo'));
      });
      test('listen', () async {
        final QuerySnapshotPlatform snapshot = await collectionReference
            .snapshots(includeMetadataChanges: true)
            .first;
        final DocumentSnapshotPlatform document = snapshot.documents[0];
        expect(document.documentID, equals('0'));
        expect(document.reference.path, equals('foo/0'));
        expect(document.data, equals(kMockDocumentSnapshotData));
        // Flush the async removeListener call
        await Future<void>.delayed(Duration.zero);
        expect(log, <Matcher>[
          isMethodCall(
            'Query#addSnapshotListener',
            arguments: <String, dynamic>{
              'app': app.name,
              'path': 'foo',
              'isCollectionGroup': false,
              'parameters': <String, dynamic>{
                'where': <List<dynamic>>[],
                'orderBy': <List<dynamic>>[],
              },
              'includeMetadataChanges': true,
            },
          ),
          isMethodCall(
            'removeListener',
            arguments: <String, dynamic>{'handle': 0},
          ),
        ]);
      });
      test('where', () async {
        final StreamSubscription<QuerySnapshotPlatform> subscription =
            collectionReference
                .where('createdAt', isLessThan: 100)
                .snapshots()
                .listen((QuerySnapshotPlatform querySnapshot) {});
        subscription.cancel(); // ignore: unawaited_futures
        await Future<void>.delayed(Duration.zero);
        expect(
          log,
          equals(<Matcher>[
            isMethodCall(
              'Query#addSnapshotListener',
              arguments: <String, dynamic>{
                'app': app.name,
                'path': 'foo',
                'isCollectionGroup': false,
                'parameters': <String, dynamic>{
                  'where': <List<dynamic>>[
                    <dynamic>['createdAt', '<', 100],
                  ],
                  'orderBy': <List<dynamic>>[],
                },
                'includeMetadataChanges': false,
              },
            ),
            isMethodCall(
              'removeListener',
              arguments: <String, dynamic>{'handle': 0},
            ),
          ]),
        );
      });
      test('where in', () async {
        final StreamSubscription<QuerySnapshotPlatform> subscription =
            collectionReference
                .where('country', whereIn: <String>['USA', 'Japan'])
                .snapshots()
                .listen((QuerySnapshotPlatform querySnapshot) {});
        subscription.cancel(); // ignore: unawaited_futures
        await Future<void>.delayed(Duration.zero);
        expect(
          log,
          equals(<Matcher>[
            isMethodCall(
              'Query#addSnapshotListener',
              arguments: <String, dynamic>{
                'app': app.name,
                'path': 'foo',
                'isCollectionGroup': false,
                'parameters': <String, dynamic>{
                  'where': <List<dynamic>>[
                    <dynamic>[
                      'country',
                      'in',
                      <String>['USA', 'Japan']
                    ],
                  ],
                  'orderBy': <List<dynamic>>[],
                },
                'includeMetadataChanges': false,
              },
            ),
            isMethodCall(
              'removeListener',
              arguments: <String, dynamic>{'handle': 0},
            ),
          ]),
        );
      });
      test('where array-contains-any', () async {
        final StreamSubscription<QuerySnapshotPlatform> subscription =
            collectionReference
                .where('regions',
                    arrayContainsAny: <String>['west-coast', 'east-coast'])
                .snapshots()
                .listen((QuerySnapshotPlatform querySnapshot) {});
        subscription.cancel(); // ignore: unawaited_futures
        await Future<void>.delayed(Duration.zero);
        expect(
          log,
          equals(<Matcher>[
            isMethodCall(
              'Query#addSnapshotListener',
              arguments: <String, dynamic>{
                'app': app.name,
                'path': 'foo',
                'isCollectionGroup': false,
                'parameters': <String, dynamic>{
                  'where': <List<dynamic>>[
                    <dynamic>[
                      'regions',
                      'array-contains-any',
                      <String>['west-coast', 'east-coast']
                    ],
                  ],
                  'orderBy': <List<dynamic>>[],
                },
                'includeMetadataChanges': false,
              },
            ),
            isMethodCall(
              'removeListener',
              arguments: <String, dynamic>{'handle': 0},
            ),
          ]),
        );
      });
      test('where field isNull', () async {
        final StreamSubscription<QuerySnapshotPlatform> subscription =
            collectionReference
                .where('profile', isNull: true)
                .snapshots()
                .listen((QuerySnapshotPlatform querySnapshot) {});
        subscription.cancel(); // ignore: unawaited_futures
        await Future<void>.delayed(Duration.zero);
        expect(
          log,
          equals(<Matcher>[
            isMethodCall(
              'Query#addSnapshotListener',
              arguments: <String, dynamic>{
                'app': app.name,
                'path': 'foo',
                'isCollectionGroup': false,
                'parameters': <String, dynamic>{
                  'where': <List<dynamic>>[
                    <dynamic>['profile', '==', null],
                  ],
                  'orderBy': <List<dynamic>>[],
                },
                'includeMetadataChanges': false,
              },
            ),
            isMethodCall(
              'removeListener',
              arguments: <String, dynamic>{'handle': 0},
            ),
          ]),
        );
      });
      test('orderBy', () async {
        final StreamSubscription<QuerySnapshotPlatform> subscription =
            collectionReference
                .orderBy('createdAt')
                .snapshots()
                .listen((QuerySnapshotPlatform querySnapshot) {});
        subscription.cancel(); // ignore: unawaited_futures
        await Future<void>.delayed(Duration.zero);
        expect(
          log,
          equals(<Matcher>[
            isMethodCall(
              'Query#addSnapshotListener',
              arguments: <String, dynamic>{
                'app': app.name,
                'path': 'foo',
                'isCollectionGroup': false,
                'parameters': <String, dynamic>{
                  'where': <List<dynamic>>[],
                  'orderBy': <List<dynamic>>[
                    <dynamic>['createdAt', false]
                  ],
                },
                'includeMetadataChanges': false,
              },
            ),
            isMethodCall(
              'removeListener',
              arguments: <String, dynamic>{'handle': 0},
            ),
          ]),
        );
      });
    });

    group('DocumentReference', () {
      test('listen', () async {
        final DocumentSnapshotPlatform snapshot = await firestore
            .document('path/to/foo')
            .snapshots(includeMetadataChanges: true)
            .first;
        expect(snapshot.documentID, equals('foo'));
        expect(snapshot.reference.path, equals('path/to/foo'));
        expect(snapshot.data, equals(kMockDocumentSnapshotData));
        // Flush the async removeListener call
        await Future<void>.delayed(Duration.zero);
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'DocumentReference#addSnapshotListener',
              arguments: <String, dynamic>{
                'app': app.name,
                'path': 'path/to/foo',
                'includeMetadataChanges': true,
              },
            ),
            isMethodCall(
              'removeListener',
              arguments: <String, dynamic>{'handle': 0},
            ),
          ],
        );
      });
      test('set', () async {
        await collectionReference
            .document('bar')
            .setData(<String, String>{'bazKey': 'quxValue'});
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'DocumentReference#setData',
              arguments: <String, dynamic>{
                'app': app.name,
                'path': 'foo/bar',
                'data': <String, String>{'bazKey': 'quxValue'},
                'options': <String, bool>{'merge': false},
              },
            ),
          ],
        );
      });
      test('merge set', () async {
        await collectionReference
            .document('bar')
            .setData(<String, String>{'bazKey': 'quxValue'}, merge: true);
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'DocumentReference#setData',
              arguments: <String, dynamic>{
                'app': app.name,
                'path': 'foo/bar',
                'data': <String, String>{'bazKey': 'quxValue'},
                'options': <String, bool>{'merge': true},
              },
            ),
          ],
        );
      });
      test('update', () async {
        await collectionReference
            .document('bar')
            .updateData(<String, String>{'bazKey': 'quxValue'});
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'DocumentReference#updateData',
              arguments: <String, dynamic>{
                'app': app.name,
                'path': 'foo/bar',
                'data': <String, String>{'bazKey': 'quxValue'},
              },
            ),
          ],
        );
      });
      test('delete', () async {
        await collectionReference.document('bar').delete();
        expect(
          log,
          equals(<Matcher>[
            isMethodCall(
              'DocumentReference#delete',
              arguments: <String, dynamic>{
                'app': app.name,
                'path': 'foo/bar',
              },
            ),
          ]),
        );
      });
      test('get', () async {
        final DocumentSnapshotPlatform snapshot =
            await collectionReference.document('bar').get(source: Source.cache);
        expect(snapshot.reference.firestore, firestore);
        expect(
          log,
          equals(<Matcher>[
            isMethodCall(
              'DocumentReference#get',
              arguments: <String, dynamic>{
                'app': app.name,
                'path': 'foo/bar',
                'source': 'cache',
              },
            ),
          ]),
        );
        log.clear();
        expect(snapshot.reference.path, equals('foo/bar'));
        expect(snapshot.data.containsKey('key1'), equals(true));
        expect(snapshot.data['key1'], equals('val1'));
        expect(snapshot.exists, isTrue);

        final DocumentSnapshotPlatform snapshot2 = await collectionReference
            .document('notExists')
            .get(source: Source.serverAndCache);
        expect(snapshot2.data, isNull);
        expect(snapshot2.exists, isFalse);
        expect(
          log,
          equals(<Matcher>[
            isMethodCall(
              'DocumentReference#get',
              arguments: <String, dynamic>{
                'app': app.name,
                'path': 'foo/notExists',
                'source': 'default',
              },
            ),
          ]),
        );

        try {
          await collectionReference.document('baz').get();
        } on PlatformException catch (e) {
          expect(e.code, equals('UNKNOWN_PATH'));
        }
      });
      test('collection', () async {
        final CollectionReferencePlatform colRef =
            collectionReference.document('bar').collection('baz');
        expect(colRef.path, equals('foo/bar/baz'));
      });
      test('parent', () async {
        final CollectionReferencePlatform colRef =
            collectionReference.document('bar').collection('baz');
        expect(colRef.parent().documentID, equals('bar'));
      });
    });

    group('Query', () {
      test('getDocumentsFromCollection', () async {
        QuerySnapshotPlatform snapshot =
            await collectionReference.getDocuments(source: Source.server);
        expect(snapshot.metadata.hasPendingWrites,
            equals(kMockSnapshotMetadata['hasPendingWrites']));
        expect(snapshot.metadata.isFromCache,
            equals(kMockSnapshotMetadata['isFromCache']));
        DocumentSnapshotPlatform document = snapshot.documents.first;
        expect(document.documentID, equals('0'));
        expect(document.reference.path, equals('foo/0'));
        expect(document.data, equals(kMockDocumentSnapshotData));

        // startAtDocument
        snapshot =
            await collectionReference.startAtDocument(document).getDocuments();
        document = snapshot.documents.first;
        expect(document.documentID, equals('0'));
        expect(document.reference.path, equals('foo/0'));
        expect(document.data, equals(kMockDocumentSnapshotData));

        // startAfterDocument
        snapshot = await collectionReference
            .startAfterDocument(document)
            .getDocuments();
        document = snapshot.documents.first;
        expect(document.documentID, equals('0'));
        expect(document.reference.path, equals('foo/0'));
        expect(document.data, equals(kMockDocumentSnapshotData));

        // endAtDocument
        snapshot =
            await collectionReference.endAtDocument(document).getDocuments();
        document = snapshot.documents.first;
        expect(document.documentID, equals('0'));
        expect(document.reference.path, equals('foo/0'));
        expect(document.data, equals(kMockDocumentSnapshotData));

        // endBeforeDocument
        snapshot = await collectionReference
            .endBeforeDocument(document)
            .getDocuments();
        document = snapshot.documents.first;
        expect(document.documentID, equals('0'));
        expect(document.reference.path, equals('foo/0'));
        expect(document.data, equals(kMockDocumentSnapshotData));

        // startAtDocument - endAtDocument
        snapshot = await collectionReference
            .startAtDocument(document)
            .endAtDocument(document)
            .getDocuments();
        document = snapshot.documents.first;
        expect(document.documentID, equals('0'));
        expect(document.reference.path, equals('foo/0'));
        expect(document.data, equals(kMockDocumentSnapshotData));

        expect(
          log,
          equals(
            <Matcher>[
              isMethodCall(
                'Query#getDocuments',
                arguments: <String, dynamic>{
                  'app': app.name,
                  'path': 'foo',
                  'isCollectionGroup': false,
                  'source': 'server',
                  'parameters': <String, dynamic>{
                    'where': <List<dynamic>>[],
                    'orderBy': <List<dynamic>>[],
                  },
                },
              ),
              isMethodCall(
                'Query#getDocuments',
                arguments: <String, dynamic>{
                  'app': app.name,
                  'path': 'foo',
                  'isCollectionGroup': false,
                  'source': 'default',
                  'parameters': <String, dynamic>{
                    'where': <List<dynamic>>[],
                    'orderBy': <List<dynamic>>[],
                    'startAtDocument': <String, dynamic>{
                      'id': '0',
                      'path': 'foo/0',
                      'data': kMockDocumentSnapshotData,
                    },
                  },
                },
              ),
              isMethodCall(
                'Query#getDocuments',
                arguments: <String, dynamic>{
                  'app': app.name,
                  'path': 'foo',
                  'isCollectionGroup': false,
                  'source': 'default',
                  'parameters': <String, dynamic>{
                    'where': <List<dynamic>>[],
                    'orderBy': <List<dynamic>>[],
                    'startAfterDocument': <String, dynamic>{
                      'id': '0',
                      'path': 'foo/0',
                      'data': kMockDocumentSnapshotData,
                    },
                  },
                },
              ),
              isMethodCall(
                'Query#getDocuments',
                arguments: <String, dynamic>{
                  'app': app.name,
                  'path': 'foo',
                  'isCollectionGroup': false,
                  'source': 'default',
                  'parameters': <String, dynamic>{
                    'where': <List<dynamic>>[],
                    'orderBy': <List<dynamic>>[],
                    'endAtDocument': <String, dynamic>{
                      'id': '0',
                      'path': 'foo/0',
                      'data': kMockDocumentSnapshotData,
                    },
                  },
                },
              ),
              isMethodCall(
                'Query#getDocuments',
                arguments: <String, dynamic>{
                  'app': app.name,
                  'path': 'foo',
                  'isCollectionGroup': false,
                  'source': 'default',
                  'parameters': <String, dynamic>{
                    'where': <List<dynamic>>[],
                    'orderBy': <List<dynamic>>[],
                    'endBeforeDocument': <String, dynamic>{
                      'id': '0',
                      'path': 'foo/0',
                      'data': kMockDocumentSnapshotData,
                    },
                  },
                },
              ),
              isMethodCall(
                'Query#getDocuments',
                arguments: <String, dynamic>{
                  'app': app.name,
                  'path': 'foo',
                  'isCollectionGroup': false,
                  'source': 'default',
                  'parameters': <String, dynamic>{
                    'where': <List<dynamic>>[],
                    'orderBy': <List<dynamic>>[],
                    'startAtDocument': <String, dynamic>{
                      'id': '0',
                      'path': 'foo/0',
                      'data': kMockDocumentSnapshotData,
                    },
                    'endAtDocument': <String, dynamic>{
                      'id': '0',
                      'path': 'foo/0',
                      'data': kMockDocumentSnapshotData,
                    },
                  },
                },
              ),
            ],
          ),
        );
      });
      test('getDocumentsFromCollectionGroup', () async {
        QuerySnapshotPlatform snapshot =
            await collectionGroupQuery.getDocuments();
        expect(snapshot.metadata.hasPendingWrites,
            equals(kMockSnapshotMetadata['hasPendingWrites']));
        expect(snapshot.metadata.isFromCache,
            equals(kMockSnapshotMetadata['isFromCache']));
        DocumentSnapshotPlatform document = snapshot.documents.first;
        expect(document.documentID, equals('0'));
        expect(document.reference.path, equals('bar/0'));
        expect(document.data, equals(kMockDocumentSnapshotData));

        // startAtDocument
        snapshot =
            await collectionGroupQuery.startAtDocument(document).getDocuments();
        document = snapshot.documents.first;
        expect(document.documentID, equals('0'));
        expect(document.reference.path, equals('bar/0'));
        expect(document.data, equals(kMockDocumentSnapshotData));

        // startAfterDocument
        snapshot = await collectionGroupQuery
            .startAfterDocument(document)
            .getDocuments();
        document = snapshot.documents.first;
        expect(document.documentID, equals('0'));
        expect(document.reference.path, equals('bar/0'));
        expect(document.data, equals(kMockDocumentSnapshotData));

        // endAtDocument
        snapshot =
            await collectionGroupQuery.endAtDocument(document).getDocuments();
        document = snapshot.documents.first;
        expect(document.documentID, equals('0'));
        expect(document.reference.path, equals('bar/0'));
        expect(document.data, equals(kMockDocumentSnapshotData));

        // endBeforeDocument
        snapshot = await collectionGroupQuery
            .endBeforeDocument(document)
            .getDocuments();
        document = snapshot.documents.first;
        expect(document.documentID, equals('0'));
        expect(document.reference.path, equals('bar/0'));
        expect(document.data, equals(kMockDocumentSnapshotData));

        // startAtDocument - endAtDocument
        snapshot = await collectionGroupQuery
            .startAtDocument(document)
            .endAtDocument(document)
            .getDocuments();
        document = snapshot.documents.first;
        expect(document.documentID, equals('0'));
        expect(document.reference.path, equals('bar/0'));
        expect(document.data, equals(kMockDocumentSnapshotData));

        expect(
          log,
          equals(
            <Matcher>[
              isMethodCall(
                'Query#getDocuments',
                arguments: <String, dynamic>{
                  'app': app.name,
                  'path': 'bar',
                  'isCollectionGroup': true,
                  'parameters': <String, dynamic>{
                    'where': <List<dynamic>>[],
                    'orderBy': <List<dynamic>>[],
                  },
                  'source': 'default',
                },
              ),
              isMethodCall(
                'Query#getDocuments',
                arguments: <String, dynamic>{
                  'app': app.name,
                  'path': 'bar',
                  'isCollectionGroup': true,
                  'parameters': <String, dynamic>{
                    'where': <List<dynamic>>[],
                    'orderBy': <List<dynamic>>[],
                    'startAtDocument': <String, dynamic>{
                      'id': '0',
                      'path': 'bar/0',
                      'data': kMockDocumentSnapshotData,
                    },
                  },
                  'source': 'default',
                },
              ),
              isMethodCall(
                'Query#getDocuments',
                arguments: <String, dynamic>{
                  'app': app.name,
                  'path': 'bar',
                  'isCollectionGroup': true,
                  'parameters': <String, dynamic>{
                    'where': <List<dynamic>>[],
                    'orderBy': <List<dynamic>>[],
                    'startAfterDocument': <String, dynamic>{
                      'id': '0',
                      'path': 'bar/0',
                      'data': kMockDocumentSnapshotData,
                    },
                  },
                  'source': 'default',
                },
              ),
              isMethodCall(
                'Query#getDocuments',
                arguments: <String, dynamic>{
                  'app': app.name,
                  'path': 'bar',
                  'isCollectionGroup': true,
                  'parameters': <String, dynamic>{
                    'where': <List<dynamic>>[],
                    'orderBy': <List<dynamic>>[],
                    'endAtDocument': <String, dynamic>{
                      'id': '0',
                      'path': 'bar/0',
                      'data': kMockDocumentSnapshotData,
                    },
                  },
                  'source': 'default',
                },
              ),
              isMethodCall(
                'Query#getDocuments',
                arguments: <String, dynamic>{
                  'app': app.name,
                  'path': 'bar',
                  'isCollectionGroup': true,
                  'source': 'default',
                  'parameters': <String, dynamic>{
                    'where': <List<dynamic>>[],
                    'orderBy': <List<dynamic>>[],
                    'endBeforeDocument': <String, dynamic>{
                      'id': '0',
                      'path': 'bar/0',
                      'data': kMockDocumentSnapshotData,
                    },
                  },
                },
              ),
              isMethodCall(
                'Query#getDocuments',
                arguments: <String, dynamic>{
                  'app': app.name,
                  'path': 'bar',
                  'isCollectionGroup': true,
                  'source': 'default',
                  'parameters': <String, dynamic>{
                    'where': <List<dynamic>>[],
                    'orderBy': <List<dynamic>>[],
                    'startAtDocument': <String, dynamic>{
                      'id': '0',
                      'path': 'bar/0',
                      'data': kMockDocumentSnapshotData,
                    },
                    'endAtDocument': <String, dynamic>{
                      'id': '0',
                      'path': 'bar/0',
                      'data': kMockDocumentSnapshotData,
                    },
                  },
                },
              ),
            ],
          ),
        );
      });

      test('FieldPath', () async {
        await collectionReference
            .where(FieldPath.documentId, isEqualTo: 'bar')
            .getDocuments();
        expect(
          log,
          equals(<Matcher>[
            isMethodCall(
              'Query#getDocuments',
              arguments: <String, dynamic>{
                'app': app.name,
                'path': 'foo',
                'isCollectionGroup': false,
                'parameters': <String, dynamic>{
                  'where': <List<dynamic>>[
                    <dynamic>[FieldPath.documentId, '==', 'bar'],
                  ],
                  'orderBy': <List<dynamic>>[],
                },
                'source': 'default',
              },
            ),
          ]),
        );
      });
      test('orderBy assertions', () async {
        // Can only order by the same field once.
        expect(() {
          firestore.collection('foo').orderBy('bar').orderBy('bar');
        }, throwsAssertionError);
        // Cannot order by unsupported types.
        expect(() {
          firestore.collection('foo').orderBy(0);
        }, throwsAssertionError);
        // Parameters cannot be null.
        expect(() {
          firestore.collection('foo').orderBy(null);
        }, throwsAssertionError);
        expect(() {
          firestore.collection('foo').orderBy('bar', descending: null);
        }, throwsAssertionError);

        // Cannot order by document id when paginating with documents.
        final DocumentReferencePlatform documentReference =
            firestore.document('foo/bar');
        final DocumentSnapshotPlatform snapshot = await documentReference.get();
        expect(() {
          firestore
              .collection('foo')
              .startAfterDocument(snapshot)
              .orderBy(FieldPath.documentId);
        }, throwsAssertionError);
      });
      test('document pagination FieldPath assertions', () async {
        final DocumentReferencePlatform documentReference =
            firestore.document('foo/bar');
        final DocumentSnapshotPlatform snapshot = await documentReference.get();
        final QueryPlatform query =
            firestore.collection('foo').orderBy(FieldPath.documentId);

        expect(() {
          query.startAfterDocument(snapshot);
        }, throwsAssertionError);
        expect(() {
          query.startAtDocument(snapshot);
        }, throwsAssertionError);
        expect(() {
          query.endAtDocument(snapshot);
        }, throwsAssertionError);
        expect(() {
          query.endBeforeDocument(snapshot);
        }, throwsAssertionError);
      });
    });

    group('FirestoreMessageCodec', () {
      const MessageCodec<dynamic> codec = FirestoreMessageCodec();
      final DateTime testTime = DateTime(2015, 10, 30, 11, 16);
      final Timestamp timestamp = Timestamp.fromDate(testTime);
      test('should encode and decode simple messages', () {
        _checkEncodeDecode<dynamic>(codec, testTime);
        _checkEncodeDecode<dynamic>(codec, timestamp);
        _checkEncodeDecode<dynamic>(
            codec, const GeoPoint(37.421939, -122.083509));
        _checkEncodeDecode<dynamic>(codec, firestore.document('foo/bar'));
      });
      test('should encode and decode composite message', () {
        final List<dynamic> message = <dynamic>[
          testTime,
          const GeoPoint(37.421939, -122.083509),
          firestore.document('foo/bar'),
        ];
        _checkEncodeDecode<dynamic>(codec, message);
      });
      test('encode and decode blob', () {
        final Uint8List bytes = Uint8List(4);
        bytes[0] = 128;
        final Blob message = Blob(bytes);
        _checkEncodeDecode<dynamic>(codec, message);
      });

      test('encode and decode FieldValue', () {
        const MessageCodec<dynamic> decoder = TestFirestoreMessageCodec();

        _checkEncodeDecode<dynamic>(
          codec,
          FieldValuePlatform(
            FieldValueFactoryPlatform.instance.arrayUnion(<int>[123]),
          ),
          decodingCodec: decoder,
        );
        _checkEncodeDecode<dynamic>(
          codec,
          FieldValuePlatform(
            FieldValueFactoryPlatform.instance.arrayRemove(<int>[123]),
          ),
          decodingCodec: decoder,
        );
        _checkEncodeDecode<dynamic>(
          codec,
          FieldValuePlatform(
            FieldValueFactoryPlatform.instance.delete(),
          ),
          decodingCodec: decoder,
        );
        _checkEncodeDecode<dynamic>(
          codec,
          FieldValuePlatform(
            FieldValueFactoryPlatform.instance.serverTimestamp(),
          ),
          decodingCodec: decoder,
        );
        _checkEncodeDecode<dynamic>(
          codec,
          FieldValuePlatform(
            FieldValueFactoryPlatform.instance.increment(1.0),
          ),
          decodingCodec: decoder,
        );
        _checkEncodeDecode<dynamic>(
          codec,
          FieldValuePlatform(
            FieldValueFactoryPlatform.instance.increment(1),
          ),
          decodingCodec: decoder,
        );
      });

      test('encode and decode FieldPath', () {
        _checkEncodeDecode<dynamic>(codec, FieldPath.documentId);
      });
    });

    group('Timestamp', () {
      test('is accurate for dates after epoch', () {
        final DateTime date = DateTime.fromMillisecondsSinceEpoch(22501);
        final Timestamp timestamp = Timestamp.fromDate(date);

        expect(timestamp.seconds, equals(22));
        expect(timestamp.nanoseconds, equals(501000000));
      });

      test('is accurate for dates before epoch', () {
        final DateTime date = DateTime.fromMillisecondsSinceEpoch(-1250);
        final Timestamp timestamp = Timestamp.fromDate(date);

        expect(timestamp.seconds, equals(-2));
        expect(timestamp.nanoseconds, equals(750000000));
      });

      test('creates equivalent timestamps regardless of factory', () {
        const int kMilliseconds = 22501;
        const int kMicroseconds = 22501000;
        final DateTime date =
            DateTime.fromMicrosecondsSinceEpoch(kMicroseconds);

        final Timestamp timestamp = Timestamp(22, 501000000);
        final Timestamp milliTimestamp =
            Timestamp.fromMillisecondsSinceEpoch(kMilliseconds);
        final Timestamp microTimestamp =
            Timestamp.fromMicrosecondsSinceEpoch(kMicroseconds);
        final Timestamp dateTimestamp = Timestamp.fromDate(date);

        expect(timestamp, equals(milliTimestamp));
        expect(milliTimestamp, equals(microTimestamp));
        expect(microTimestamp, equals(dateTimestamp));
      });

      test('correctly compares timestamps', () {
        final Timestamp alpha = Timestamp.fromDate(DateTime(2017, 5, 11));
        final Timestamp beta1 = Timestamp.fromDate(DateTime(2018, 2, 19));
        final Timestamp beta2 = Timestamp.fromDate(DateTime(2018, 4, 2));
        final Timestamp beta3 = Timestamp.fromDate(DateTime(2018, 4, 20));
        final Timestamp preview = Timestamp.fromDate(DateTime(2018, 6, 20));
        final List<Timestamp> inOrder = <Timestamp>[
          alpha,
          beta1,
          beta2,
          beta3,
          preview
        ];

        final List<Timestamp> timestamps = <Timestamp>[
          beta2,
          beta3,
          alpha,
          preview,
          beta1
        ];
        timestamps.sort();
        expect(_deepEqualsList(timestamps, inOrder), isTrue);
      });

      test('rejects dates outside RFC 3339 range', () {
        final List<DateTime> invalidDates = <DateTime>[
          DateTime.fromMillisecondsSinceEpoch(-70000000000000),
          DateTime.fromMillisecondsSinceEpoch(300000000000000),
        ];

        invalidDates.forEach((DateTime date) {
          expect(() => Timestamp.fromDate(date), throwsArgumentError);
        });
      });
    });

    group('WriteBatch', () {
      test('set', () async {
        final WriteBatchPlatform batch = firestore.batch();
        batch.setData(
          collectionReference.document('bar'),
          <String, String>{'bazKey': 'quxValue'},
        );
        await batch.commit();
        expect(
          log,
          <Matcher>[
            isMethodCall('WriteBatch#create', arguments: <String, dynamic>{
              'app': app.name,
            }),
            isMethodCall(
              'WriteBatch#setData',
              arguments: <String, dynamic>{
                'app': app.name,
                'handle': 1,
                'path': 'foo/bar',
                'data': <String, String>{'bazKey': 'quxValue'},
                'options': <String, bool>{'merge': false},
              },
            ),
            isMethodCall(
              'WriteBatch#commit',
              arguments: <String, dynamic>{
                'handle': 1,
              },
            ),
          ],
        );
      });
      test('merge set', () async {
        final WriteBatchPlatform batch = firestore.batch();
        batch.setData(
          collectionReference.document('bar'),
          <String, String>{'bazKey': 'quxValue'},
          merge: true,
        );
        await batch.commit();
        expect(
          log,
          <Matcher>[
            isMethodCall('WriteBatch#create', arguments: <String, dynamic>{
              'app': app.name,
            }),
            isMethodCall('WriteBatch#setData', arguments: <String, dynamic>{
              'app': app.name,
              'handle': 1,
              'path': 'foo/bar',
              'data': <String, String>{'bazKey': 'quxValue'},
              'options': <String, bool>{'merge': true},
            }),
            isMethodCall(
              'WriteBatch#commit',
              arguments: <String, dynamic>{
                'handle': 1,
              },
            ),
          ],
        );
      });
      test('update', () async {
        final WriteBatchPlatform batch = firestore.batch();
        batch.updateData(
          collectionReference.document('bar'),
          <String, String>{'bazKey': 'quxValue'},
        );
        await batch.commit();
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'WriteBatch#create',
              arguments: <String, dynamic>{
                'app': app.name,
              },
            ),
            isMethodCall(
              'WriteBatch#updateData',
              arguments: <String, dynamic>{
                'app': app.name,
                'handle': 1,
                'path': 'foo/bar',
                'data': <String, String>{'bazKey': 'quxValue'},
              },
            ),
            isMethodCall(
              'WriteBatch#commit',
              arguments: <String, dynamic>{
                'handle': 1,
              },
            ),
          ],
        );
      });
      test('delete', () async {
        final WriteBatchPlatform batch = firestore.batch();
        batch.delete(collectionReference.document('bar'));
        await batch.commit();
        expect(
          log,
          <Matcher>[
            isMethodCall(
              'WriteBatch#create',
              arguments: <String, dynamic>{
                'app': app.name,
              },
            ),
            isMethodCall(
              'WriteBatch#delete',
              arguments: <String, dynamic>{
                'app': app.name,
                'handle': 1,
                'path': 'foo/bar',
              },
            ),
            isMethodCall(
              'WriteBatch#commit',
              arguments: <String, dynamic>{
                'handle': 1,
              },
            ),
          ],
        );
      });
    });
  });
}

void _checkEncodeDecode<T>(
  MessageCodec<T> codec,
  T message, {
  MessageCodec<T> decodingCodec,
}) {
  MessageCodec<T> decoder = decodingCodec ?? codec;

  final ByteData encoded = codec.encodeMessage(message);
  final T decoded = decoder.decodeMessage(encoded);
  if (message == null) {
    expect(encoded, isNull);
    expect(decoded, isNull);
  } else {
    expect(_deepEquals(message, decoded), isTrue);
    final ByteData encodedAgain = codec.encodeMessage(decoded);
    expect(
      encodedAgain.buffer.asUint8List(),
      orderedEquals(encoded.buffer.asUint8List()),
    );
  }
}

bool _deepEquals(dynamic valueA, dynamic valueB) {
  if (valueA is TypedData) {
    return valueB is TypedData && _deepEqualsTypedData(valueA, valueB);
  }
  if (valueA is List) return valueB is List && _deepEqualsList(valueA, valueB);
  if (valueA is Map) return valueB is Map && _deepEqualsMap(valueA, valueB);
  if (valueA is double && valueA.isNaN) return valueB is double && valueB.isNaN;
  if (valueA is FieldValuePlatform) {
    return valueB is FieldValuePlatform &&
        _deepEqualsFieldValue(valueA, valueB);
  }
  if (valueA is FieldPath) {
    return valueB is FieldPath && valueA.type == valueB.type;
  }
  return valueA == valueB;
}

bool _deepEqualsTypedData(TypedData valueA, TypedData valueB) {
  if (valueA is ByteData) {
    return valueB is ByteData &&
        _deepEqualsList(
            valueA.buffer.asUint8List(), valueB.buffer.asUint8List());
  }
  if (valueA is Uint8List) {
    return valueB is Uint8List && _deepEqualsList(valueA, valueB);
  }
  if (valueA is Int32List) {
    return valueB is Int32List && _deepEqualsList(valueA, valueB);
  }
  if (valueA is Int64List) {
    return valueB is Int64List && _deepEqualsList(valueA, valueB);
  }
  if (valueA is Float64List) {
    return valueB is Float64List && _deepEqualsList(valueA, valueB);
  }
  throw 'Unexpected typed data: $valueA';
}

bool _deepEqualsList(List<dynamic> valueA, List<dynamic> valueB) {
  if (valueA.length != valueB.length) return false;
  for (int i = 0; i < valueA.length; i++) {
    if (!_deepEquals(valueA[i], valueB[i])) return false;
  }
  return true;
}

bool _deepEqualsMap(
  Map<dynamic, dynamic> valueA,
  Map<dynamic, dynamic> valueB,
) {
  if (valueA.length != valueB.length) return false;
  for (final dynamic key in valueA.keys) {
    if (!valueB.containsKey(key) || !_deepEquals(valueA[key], valueB[key])) {
      return false;
    }
  }
  return true;
}

bool _deepEqualsFieldValue(FieldValuePlatform a, FieldValuePlatform b) {
  MethodChannelFieldValue valueA = FieldValuePlatform.getDelegate(a);
  MethodChannelFieldValue valueB = FieldValuePlatform.getDelegate(b);

  if (valueA.type != valueB.type) return false;
  if (valueA.value == null) return valueB.value == null;
  if (valueA.value is List) return _deepEqualsList(valueA.value, valueB.value);
  if (valueA.value is Map) return _deepEqualsMap(valueA.value, valueB.value);
  return valueA.value == valueB.value;
}
