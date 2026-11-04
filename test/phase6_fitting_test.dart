import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/shop/virtual_fitting_screen.dart';
void main(){
 testWidgets('size guide rejects NaN instead of calculating a fictitious size',(tester)async{
  await tester.pumpWidget(const MaterialApp(home:VirtualFittingScreen()));
  final fields=find.byType(TextFormField);
  for(var i=0;i<fields.evaluate().length;i++){
   await tester.ensureVisible(fields.at(i));await tester.enterText(fields.at(i),['NaN','70','94','80','90'][i]);
  }
  await tester.ensureVisible(find.text('Calcular mis tallas'));await tester.tap(find.text('Calcular mis tallas'));await tester.pumpAndSettle();
  expect(find.text('Número inválido'),findsOneWidget);
  expect(find.text('Tu guía de tallas'),findsNothing);
 });
}
