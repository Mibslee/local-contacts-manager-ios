//
//  本地通讯录管家Tests.swift
//  本地通讯录管家Tests
//
//  Created by Peishen Li on 2026/3/20.
//

import XCTest
@testable import 本地通讯录管家
import Contacts

class 本地通讯录管家Tests: XCTestCase {

    func testExample() {
        // Write your test here and use APIs like `XCTAssert` to check expected conditions.
        XCTAssertTrue(true, "Example test should pass")
    }
    
    func testContactItemCreation() {
        // 测试ContactItem的创建
        let contact = ContactItem(
            id: "test123",
            familyName: "张",
            givenName: "三",
            phoneNumbers: [
                ContactItem.LabeledValue(label: "手机", value: "13800138000")
            ],
            emailAddresses: [
                ContactItem.LabeledValue(label: "邮箱", value: "test@example.com")
            ],
            organization: "测试公司",
            department: "技术部"
        )
        
        XCTAssertEqual(contact.id, "test123")
        XCTAssertEqual(contact.familyName, "张")
        XCTAssertEqual(contact.givenName, "三")
        XCTAssertEqual(contact.phoneNumbers.count, 1)
        XCTAssertEqual(contact.emailAddresses.count, 1)
        XCTAssertEqual(contact.organization, "测试公司")
        XCTAssertEqual(contact.department, "技术部")
    }
    
    func testContactItemFullName() {
        // 测试fullName计算属性
        let contact = ContactItem(
            id: "test456",
            familyName: "李",
            givenName: "四"
        )
        
        XCTAssertEqual(contact.fullName, "李四")
    }
    
    func testContactItemInitials() {
        // 测试initials计算属性
        let contact = ContactItem(
            id: "test789",
            familyName: "王",
            givenName: "五"
        )
        
        XCTAssertEqual(contact.initials, "王五")
    }
    
    func testContactItemEmptyCheck() {
        // 测试isEmpty计算属性
        let emptyContact = ContactItem(
            id: "empty1",
            familyName: "",
            givenName: "",
            phoneNumbers: [],
            emailAddresses: []
        )
        
        XCTAssertTrue(emptyContact.isEmpty)
        
        let nonEmptyContact = ContactItem(
            id: "nonempty1",
            familyName: "",
            givenName: "",
            phoneNumbers: [ContactItem.LabeledValue(label: "手机", value: "13800138000")],
            emailAddresses: []
        )
        
        XCTAssertFalse(nonEmptyContact.isEmpty)
    }
    
    func testHealthAnalyzer() {
        // 测试HealthAnalyzer
        let contacts = [
            ContactItem(
                id: "test1",
                familyName: "张",
                givenName: "三",
                phoneNumbers: [ContactItem.LabeledValue(label: "手机", value: "13800138000")],
                emailAddresses: [ContactItem.LabeledValue(label: "邮箱", value: "test1@example.com")]
            ),
            ContactItem(
                id: "test2",
                familyName: "李",
                givenName: "四",
                phoneNumbers: [ContactItem.LabeledValue(label: "手机", value: "13900139000")],
                emailAddresses: []
            )
        ]
        
        let report = HealthAnalyzer.analyze(contacts)
        
        XCTAssertEqual(report.totalContacts, 2)
        XCTAssertEqual(report.totalPhoneNumbers, 2)
        XCTAssertEqual(report.totalEmails, 1)
    }
    
    func testContactItemHashable() {
        // 测试ContactItem的Hashable协议
        let contact1 = ContactItem(
            id: "hash1",
            familyName: "赵",
            givenName: "六"
        )
        
        let contact2 = ContactItem(
            id: "hash1",
            familyName: "赵",
            givenName: "六"
        )
        
        XCTAssertEqual(contact1, contact2)
        XCTAssertEqual(contact1.hashValue, contact2.hashValue)
    }
    
    func testContactItemLabeledValue() {
        // 测试LabeledValue
        let labeledValue = ContactItem.LabeledValue(
            label: "手机",
            value: "13800138000"
        )
        
        XCTAssertEqual(labeledValue.label, "手机")
        XCTAssertEqual(labeledValue.value, "13800138000")
        XCTAssertNotNil(labeledValue.id)
    }
}
